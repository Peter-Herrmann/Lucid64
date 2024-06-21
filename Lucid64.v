///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: Lucid64                                                                          //
// Description: A 5 stage RV64 core written in standard Verilog                                  //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: CC-BY-NC-ND-4.0                                                      //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module Lucid64 #(parameter VADDR = 39, parameter RESET_ADDR = 0) (
    input                   clk_i,
    input                   rst_ni,

    input                   m_ext_inter_i,
    input                   m_soft_inter_i,
    input                   m_timer_inter_i,

    input [`XLEN-1:0]       time_i,

    output                  fencei_flush_ao,

    // Instruction Memory Interface (RI5CY subset of OBI, read-only)
    output wire             imem_req_o,
    input                   imem_gnt_i,
    output wire [VADDR-1:0] imem_addr_ao,

    input                   imem_rvalid_i,
    input        [31:0]     imem_rdata_i,

    // Data Memory Interface (RI5CY subset of OBI, read-write)
    output wire             dmem_req_o,
    input                   dmem_gnt_i,
    output wire [VADDR-1:0] dmem_addr_ao,
    output wire             dmem_we_ao,
    output wire  [7:0]      dmem_be_ao,
    output wire [`XLEN-1:0] dmem_wdata_ao,
    
    input                   dmem_rvalid_i,
    input       [`XLEN-1:0] dmem_rdata_i
    );

    // Stage Management Signals
    wire FCH_squash, DCD_squash, EXE_squash, MEM_squash, WB_squash;
    wire FCH_bubble, DCD_bubble, EXE_bubble, MEM_bubble, WB_bubble;
    wire FCH_stall,  DCD_stall,  EXE_stall,  MEM_stall,  WB_stall;
    wire FCH_valid,  DCD_valid,  EXE_valid,  MEM_valid,  WB_valid;

    wire mret, wait_for_int, fencei_flush, WB_inst_retired;
    wire [VADDR-1:0] trap_ret_addr;

    // Hazard signals
    wire load_use_haz, csr_load_use_haz, imem_stall, dmem_stall, alu_stall, fencei;

    // Exception signals
    wire illegal_inst_ex, ecall_ex, ebreak_ex, unalign_load_ex, unalign_store_ex;

    // Interrupt signals
    wire [VADDR-1:0] csr_branch_addr;
    wire             pipeline_interrupt, csr_interrupt;

    // Register File Signals
    wire [4:0]       rs1_idx,  rs2_idx,  rd_idx;
    wire [`XLEN-1:0] rs1_data, rs2_data, rd_data;
    wire             rd_wr_en;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //            ____               _                ____  _                                    //
    //           |  _ \(_)_ __   ___| (_)_ __   ___  / ___|| |_ __ _  __ _  ___  ___             //
    //           | |_) | | '_ \ / _ \ | | '_ \ / _ \ \___ \| __/ _` |/ _` |/ _ \/ __|            //
    //           |  __/| | |_) |  __/ | | | | |  __/  ___) | || (_| | (_| |  __/\__ \            //
    //           |_|   |_| .__/ \___|_|_|_| |_|\___| |____/ \__\__,_|\__, |\___||___/            //
    //                   |_|                                         |___/                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                            Fetch                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    wire             EXE_branch, DCD_compress_instr;
    wire [VADDR-1:0] EXE_pc_target_addr, FCH_pc, FCH_next_pc;


    fetch_stage #(.VADDR(VADDR), .RESET_ADDR(RESET_ADDR)) FCH (
        //======= Clocks, Resets, and Stage Controls ========//
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),

        .squash_i           (FCH_squash),
        .bubble_i           (FCH_bubble),
        .stall_i            (FCH_stall),
        .fencei_i           (fencei_flush),
        .compressed_instr_i (DCD_compress_instr),

        //============== Branch Control Inputs ==============//
        .branch_i           (EXE_branch),
        .target_addr_i      (EXE_pc_target_addr),
        
        .csr_branch_i       (pipeline_interrupt),
        .csr_branch_addr_i  (csr_branch_addr),

        .trap_ret_i         (mret),
        .trap_ret_addr_i    (trap_ret_addr),
    
        //========== Instruction Memory Interface ===========//
        .imem_req_o         (imem_req_o),
        .imem_addr_ao       (imem_addr_ao),
        .imem_gnt_i         (imem_gnt_i),
        .imem_rvalid_i      (imem_rvalid_i),

        .imem_stall_ao      (imem_stall),

        //================ Pipeline Outputs =================//
        .valid_o            (FCH_valid),
        .pc_o               (FCH_pc),
        .next_pc_o          (FCH_next_pc)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                            Decode                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    // Register File Signals
    wire [4:0]       DCD_rs1_idx,  DCD_rs2_idx,  DCD_rd_idx;
    wire             DCD_rs1_used, DCD_rs2_used, DCD_rd_wr_en;
    wire [`XLEN-1:0] DCD_rs1_data, DCD_rs2_data;
    wire [4:0]       DCD_rd_wr_src_1h;
    // ALU Signals
    wire [5:0]       DCD_alu_operation;
    wire [`XLEN-1:0] DCD_alu_op_a,       DCD_alu_op_b;
    wire             DCD_alu_uses_rs1,   DCD_alu_uses_rs2;
    // Memory Signals
    wire [3:0]       DCD_mem_width_1h;
    wire             DCD_mem_rd,   DCD_mem_wr,   DCD_mem_sign;
    // Flow Control Signals
    wire             DCD_branch;
    wire [VADDR-1:0] DCD_next_pc, DCD_pc;
    wire [5:0]       DCD_br_cond_1h;
    // CSR Control Signals
    wire             DCD_csr_wr_en, EXE_csr_wr_en, csr_rd_en;
    wire [2:0]       DCD_csr_op_1h;
    wire [11:0]      DCD_csr_addr, csr_rd_addr;
    wire [11:0]      csr_wr_addr;
    // Traps and Exceptions
    wire DCD_ecall_ex, DCD_ebreak_ex, DCD_mret, DCD_wait_for_int, DCD_illegal_inst_ex, DCD_fencei;

    decode_stage #(.VADDR(VADDR)) DCD (
        //======= Clocks, Resets, and Stage Controls ========//
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        
        .squash_i           (DCD_squash),
        .bubble_i           (DCD_bubble),
        .stall_i            (DCD_stall),
        //=============== Fetch Stage Inputs ================//
        .pc_i               (FCH_pc),
        .next_pc_i          (FCH_next_pc),
        .valid_i            (FCH_valid),
        // Instruction from memory
        .inst_i             (imem_rdata_i),
        // ============== Fetch Stage Feedback ==============//
        .compressed_instr_ao(DCD_compress_instr),
        //======= Register File Async Read Interface ========//
        .rs1_idx_ao         (rs1_idx),
        .rs2_idx_ao         (rs2_idx),
        .rs1_data_i         (rs1_data),
        .rs2_data_i         (rs2_data),
        //=============== CSR Read Interface ================//
        .csr_addr_ao        (csr_rd_addr),
        .csr_rd_en_ao       (csr_rd_en),
        // CSR Load Use Hazard Inputs
        .EXE_csr_addr_i     (csr_wr_addr),
        .EXE_csr_wr_en_i    (EXE_csr_wr_en),
        .csr_load_use_haz_ao(csr_load_use_haz),
        //================ Pipeline Outputs =================//
        .valid_o            (DCD_valid),
        // Register Source 1 (rs1)
        .rs1_idx_o          (DCD_rs1_idx),
        .rs1_used_o         (DCD_rs1_used),
        .rs1_data_o         (DCD_rs1_data),
        // Register Source 2 (rs2)
        .rs2_idx_o          (DCD_rs2_idx),
        .rs2_used_o         (DCD_rs2_used),
        .rs2_data_o         (DCD_rs2_data),
        // Destination Register (rd)
        .rd_idx_o           (DCD_rd_idx),
        .rd_wr_en_o         (DCD_rd_wr_en),
        .rd_wr_src_1h_o     (DCD_rd_wr_src_1h),
        // ALU Operation and Operands
        .alu_operation_o    (DCD_alu_operation),
        .alu_op_a_o         (DCD_alu_op_a),
        .alu_op_b_o         (DCD_alu_op_b),
        .alu_uses_rs1_o     (DCD_alu_uses_rs1),
        .alu_uses_rs2_o     (DCD_alu_uses_rs2),
        // Load/Store
        .mem_width_1h_o     (DCD_mem_width_1h),
        .mem_rd_o           (DCD_mem_rd),
        .mem_wr_o           (DCD_mem_wr),
        .mem_sign_o         (DCD_mem_sign),
        // Flow Control
        .branch_o           (DCD_branch),
        .pc_o               (DCD_pc),
        .next_pc_o          (DCD_next_pc),
        .br_cond_1h_o       (DCD_br_cond_1h),
        // CSR Control
        .csr_wr_en_o        (DCD_csr_wr_en),
        .csr_op_1h_o        (DCD_csr_op_1h),
        .csr_addr_o         (DCD_csr_addr),
        // Traps and Exceptions
        .ecall_ex_o         (DCD_ecall_ex),
        .ebreak_ex_o        (DCD_ebreak_ex),
        .illegal_inst_ex_o  (DCD_illegal_inst_ex),
        .mret_o             (DCD_mret),
        .wait_for_int_o     (DCD_wait_for_int),
        .fencei_o           (DCD_fencei)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           Execute                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    wire             EXE_rd_wr_en, EXE_rd_wr_src_load;
    wire [`XLEN-1:0] EXE_rs2_data,  EXE_rd_data, EXE_csr_wdata, EXE_csr_rdata; 
    wire [VADDR-1:0] EXE_pc, EXE_dmem_addr;
    wire [4:0]       EXE_rd_idx;
    wire [3:0]       EXE_mem_width_1h;
    wire             EXE_rd, EXE_wr, EXE_sign, EXE_wr_a;

    execute_stage #(.VADDR(VADDR)) EXE (
        //======= Clocks, Resets, and Stage Controls ========//
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        
        .squash_i           (EXE_squash),
        .bubble_i           (EXE_bubble),
        .stall_i            (EXE_stall),

        //============== Decode Stage Inputs ================//
        .valid_i            (DCD_valid),
        // Register Source 1 (rs1)
        .rs1_idx_i          (DCD_rs1_idx),
        .rs1_used_i         (DCD_rs1_used),
        .rs1_data_i         (DCD_rs1_data),
        // Register Source 2 (rs2)
        .rs2_idx_i          (DCD_rs2_idx),
        .rs2_used_i         (DCD_rs2_used),
        .rs2_data_i         (DCD_rs2_data),
        // Destination Register (rd)
        .rd_idx_i           (DCD_rd_idx),
        .rd_wr_en_i         (DCD_rd_wr_en),
        .rd_wr_src_1h_i     (DCD_rd_wr_src_1h),
        // ALU Operation and Operands
        .alu_operation_i    (DCD_alu_operation),
        .alu_op_a_i         (DCD_alu_op_a),
        .alu_op_b_i         (DCD_alu_op_b),
        .alu_uses_rs1_i     (DCD_alu_uses_rs1),
        .alu_uses_rs2_i     (DCD_alu_uses_rs2),
        // Load/Store
        .mem_width_1h_i     (DCD_mem_width_1h),
        .mem_rd_i           (DCD_mem_rd),
        .mem_wr_i           (DCD_mem_wr),
        .mem_sign_i         (DCD_mem_sign),
        // Flow Control
        .branch_i           (DCD_branch),
        .pc_i               (DCD_pc),
        .next_pc_i          (DCD_next_pc),
        .br_cond_1h_i       (DCD_br_cond_1h),
        // CSR Control
        .csr_wr_en_i        (DCD_csr_wr_en),
        .csr_op_1h_i        (DCD_csr_op_1h),
        .csr_wr_addr_i      (DCD_csr_addr),
        // Traps and Exceptions
        .ecall_ex_i         (DCD_ecall_ex),
        .ebreak_ex_i        (DCD_ebreak_ex),
        .illegal_inst_ex_i  (DCD_illegal_inst_ex),
        .mret_i             (DCD_mret),
        .wait_for_int_i     (DCD_wait_for_int),
        .fencei_i           (DCD_fencei),

        //============= Forwarded Register Data =============//
        .MEM_rd_wr_en_i     (rd_wr_en),
        .MEM_valid_i        (WB_valid),
        .MEM_rd_idx_i       (rd_idx),
        .MEM_rd_data_i      (rd_data),

        //================== CSR Interface ==================//
        .csr_rdata_i        (EXE_csr_rdata),
        .csr_wdata_ao       (EXE_csr_wdata),
        .csr_wr_addr_ao     (csr_wr_addr),
        .csr_wr_en_ao       (EXE_csr_wr_en),

        //===============Traps and Exceptions================//
        .ecall_ex_ao        (ecall_ex),
        .ebreak_ex_ao       (ebreak_ex),
        .illegal_inst_ex_ao (illegal_inst_ex),
        .mret_ao            (mret),
        .wait_for_int_ao    (wait_for_int),
        .fencei_ao          (fencei),

        //============== Flow Control Outputs ===============//
        .branch_o           (EXE_branch),
        .target_addr_o      (EXE_pc_target_addr),

        .load_use_haz_ao    (load_use_haz),
        .alu_stall_o        (alu_stall),
        .mem_wr_ao          (EXE_wr_a),

        //================ Pipeline Outputs =================//
        .valid_o            (EXE_valid),
        .dmem_addr_o        (EXE_dmem_addr),
        .rs2_data_o         (EXE_rs2_data),
        // Destination Register (rd)
        .rd_data_o          (EXE_rd_data),
        .rd_idx_o           (EXE_rd_idx),
        .rd_wr_en_o         (EXE_rd_wr_en),
        .rd_wr_src_load_o   (EXE_rd_wr_src_load),
        // Load/Store
        .mem_width_1h_o     (EXE_mem_width_1h),
        .mem_rd_o           (EXE_rd),
        .mem_wr_o           (EXE_wr),
        .mem_sign_o         (EXE_sign),
        // Program Counter
        .pc_o               (EXE_pc)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                            Memory                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    wire             MEM_rd_wr_en, MEM_rd_wr_src_load;
    wire [3:0]       MEM_mem_width_1h;
    wire [4:0]       MEM_rd_idx;
    wire [`XLEN-1:0] MEM_rd_data;
    wire [2:0]       MEM_byte_addr;
    wire             MEM_sign;


    memory_stage #(.VADDR(VADDR)) MEM (
        //======= Clocks, Resets, and Stage Controls ========//
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),

        .squash_i           (MEM_squash),
        .bubble_i           (MEM_bubble),
        .stall_i            (MEM_stall),

        //============== Execute Stage Inputs ===============//
        .valid_i            (EXE_valid),
        .dmem_full_addr_i   (EXE_dmem_addr),
        .rs2_data_i         (EXE_rs2_data),
        // Destination Register (rd)
        .rd_data_i          (EXE_rd_data),
        .rd_idx_i           (EXE_rd_idx),
        .rd_wr_en_i         (EXE_rd_wr_en),
        .rd_wr_src_load_i   (EXE_rd_wr_src_load),
        // Load/Store
        .mem_width_1h_i     (EXE_mem_width_1h),
        .mem_rd_i           (EXE_rd),
        .mem_wr_i           (EXE_wr),
        .mem_sign_i         (EXE_sign),
        
        //============== Data Memory Interface ==============//
        .dmem_req_o         (dmem_req_o),
        .dmem_gnt_i         (dmem_gnt_i),
        .dmem_addr_ao       (dmem_addr_ao),
        .dmem_we_ao         (dmem_we_ao),
        .dmem_be_ao         (dmem_be_ao),
        .dmem_wdata_ao      (dmem_wdata_ao),
        .dmem_rvalid_i      (dmem_rvalid_i),

        .dmem_stall_ao      (dmem_stall),
        .unalign_store_ex_ao(unalign_store_ex),
        .unalign_load_ex_ao (unalign_load_ex),

        //================ Pipeline Outputs =================//
        .valid_o            (MEM_valid),
        // Destination Register (rd)
        .rd_data_o          (MEM_rd_data),
        .rd_idx_o           (MEM_rd_idx),
        .rd_wr_en_o         (MEM_rd_wr_en),
        .rd_wr_src_load_o   (MEM_rd_wr_src_load),
        // Load/Store
        .mem_width_1h_o     (MEM_mem_width_1h),
        .mem_sign_o         (MEM_sign),
        .byte_addr_o        (MEM_byte_addr)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          Writeback                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    writeback_stage WB (
        //======= Clocks, Resets, and Stage Controls ========//
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),

        .squash_i           (WB_squash),
        .bubble_i           (WB_bubble),
        .stall_i            (WB_stall),

        //============= Memory Pipeline Inputs ==============//
        .valid_i            (MEM_valid),
        // Destination Register (rd)
        .rd_data_i          (MEM_rd_data),
        .rd_idx_i           (MEM_rd_idx),
        .rd_wr_en_i         (MEM_rd_wr_en),
        .rd_wr_src_load_i   (MEM_rd_wr_src_load),
        // Data Memory Load Inputs
        .dmem_rdata_i       (dmem_rdata_i),
        .mem_width_1h_i     (MEM_mem_width_1h),
        .mem_sign_i         (MEM_sign),
        .byte_addr_i        (MEM_byte_addr),

        //============= Register File Controls ==============//
        .rd_data_ao         (rd_data),
        .rd_idx_ao          (rd_idx),
        .rd_wr_en_ao        (rd_wr_en),

        .inst_retired_ao    (WB_inst_retired),
        .valid_ao           (WB_valid)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                ____                                             _                         //
    //               / ___|___  _ __ ___  _ __   ___  _ __   ___ _ __ | |_ ___                   //
    //              | |   / _ \| '_ ` _ \| '_ \ / _ \| '_ \ / _ \ '_ \| __/ __|                  //
    //              | |__| (_) | | | | | | |_) | (_) | | | |  __/ | | | |_\__ \                  //
    //               \____\___/|_| |_| |_| .__/ \___/|_| |_|\___|_| |_|\__|___/                  //
    //                                   |_|                                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    Pipeline Controller                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    pipeline_controller pipeline_controller_inst (
        //================= Clocks, Resets ==================//
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),

        //================= Hazard Inputs ===================//
        .imem_stall_i       (imem_stall),
        .dmem_stall_i       (dmem_stall),
        .load_use_haz_i     (load_use_haz),
        .csr_load_use_haz_i (csr_load_use_haz),
        .alu_stall_i        (alu_stall),
        .fencei_i           (fencei),
        .mem_exc_i          (unalign_store_ex || unalign_load_ex),
        .trap_i             (mret || ecall_ex || ebreak_ex),

        //============= Pipeline State Inputs ===============//
        .EXE_branch_i       (EXE_branch),
        .EXE_write_i        (EXE_wr_a),
        .MEM_write_i        (dmem_we_ao),
        .valid_inst_in_pipe_i(FCH_valid | DCD_valid | EXE_valid | MEM_valid | WB_valid),

        //============= Interrupt Controls ==================//
        .wait_for_int_i     (wait_for_int),
        .interrupt_i        (csr_interrupt),
        .interrupt_o        (pipeline_interrupt),

        //============= Stage Control Outputs ===============//
        .FCH_squash_o       (FCH_squash),
        .FCH_bubble_o       (FCH_bubble),
        .FCH_stall_o        (FCH_stall),

        .DCD_squash_o       (DCD_squash),
        .DCD_bubble_o       (DCD_bubble),
        .DCD_stall_o        (DCD_stall),

        .EXE_squash_o       (EXE_squash),
        .EXE_bubble_o       (EXE_bubble),
        .EXE_stall_o        (EXE_stall),

        .MEM_squash_o       (MEM_squash),
        .MEM_bubble_o       (MEM_bubble),
        .MEM_stall_o        (MEM_stall),

        .WB_squash_o        (WB_squash),
        .WB_bubble_o        (WB_bubble),
        .WB_stall_o         (WB_stall),

        .fencei_flush_ao    (fencei_flush)
    );

    assign fencei_flush_ao = fencei_flush;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       Register File                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    register_file #(.XLEN(`XLEN)) i_register_file (
        .clk_i        (clk_i),

        .rs1_idx_i    (rs1_idx),
        .rs2_idx_i    (rs2_idx),

        .rd_idx_i     (rd_idx),
        .wr_data_i    (rd_data),
        .wr_en_i      (rd_wr_en),

        .rs1_data_ao  (rs1_data),
        .rs2_data_ao  (rs2_data) 
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                            Control and Status Registers (CSRs)                            //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [VADDR-1:0] EXE_exc_pc = DCD_pc;
    wire [VADDR-1:0] MEM_exc_pc = EXE_pc;

    csr #(.VADDR(VADDR)) i_csr (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),

        .rd_en_i            (csr_rd_en),
        .rd_addr_i          (csr_rd_addr),
        .rdata_o            (EXE_csr_rdata),

        .wr_en_i            (EXE_csr_wr_en),
        .wr_addr_i          (csr_wr_addr),
        .wdata_i            (EXE_csr_wdata),

        .unalign_load_ex_i  (unalign_load_ex),
        .unalign_store_ex_i (unalign_store_ex),
        .ecall_ex_i         (ecall_ex),
        .ebreak_ex_i        (ebreak_ex),
        .illegal_inst_ex_i  (illegal_inst_ex),

        .m_ext_inter_i      (m_ext_inter_i),
        .m_soft_inter_i     (m_soft_inter_i),
        .m_timer_inter_i    (m_timer_inter_i),

        .mret_i             (mret),
        .instr_retired_i    (WB_inst_retired),
        .time_i             (time_i),

        .EXE_exc_pc_i       (EXE_exc_pc),
        .MEM_exc_pc_i       (MEM_exc_pc),
        .load_store_bad_addr(EXE_dmem_addr),
        .csr_interrupt_ao   (csr_interrupt),
        .csr_branch_addr_o  (csr_branch_addr),

        .trap_ret_addr_o    (trap_ret_addr)
    );


endmodule


///////////////////////////////////////////////////////////////////////////////////////////////////
////   Copyright 2024 Peter Herrmann                                                           ////
////                                                                                           ////
////   Licensed under the Creative Commons Attribution-NonCommercial-NoDerivatives 4.0         ////
////   International License (the "License"); you may not use this file except in compliance   ////
////   with the License. You may obtain a copy of the License at                               ////
////                                                                                           ////
////       https://creativecommons.org/licenses/by-nc-nd/4.0/                                  ////
////                                                                                           ////
////   Unless required by applicable law or agreed to in writing, software                     ////
////   distributed under the License is distributed on an "AS IS" BASIS,                       ////
////   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.                ////
////   See the License for the specific language governing permissions and                     ////
////   limitations under the License.                                                          ////
///////////////////////////////////////////////////////////////////////////////////////////////////
