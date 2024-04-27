///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: Lucid64                                                                          //
// Description: A 5 stage RV64 core written in standard Verilog                                  //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module Lucid64 (
    input               clk_i,
    input               rst_ni,

    output wire         alert_o,

    // Instruction Memory Interface (RI5CY subset of OBI)
    output wire         imem_req_o,
    input               imem_gnt_i,
    output wire  [63:0] imem_addr_o,
    output wire         imem_we_o,
    output wire  [3:0]  imem_be_o,
    output wire  [31:0] imem_wdata_o,
    input               imem_rvalid_i,
    input        [31:0] imem_rdata_i,

    // Data Memory Interface (RI5CY subset of OBI)
    output wire         dmem_req_o,
    input               dmem_gnt_i,
    output wire  [63:0] dmem_addr_o,
    output wire         dmem_we_o,
    output wire  [7:0]  dmem_be_o,
    output wire  [63:0] dmem_wdata_o,
    input               dmem_rvalid_i,
    input        [63:0] dmem_rdata_i
);

    // Stage Management Signals
    wire         FCH_squash, DCD_squash, EXE_squash, MEM_squash, WB_squash;
    wire         FCH_stall,  DCD_stall,  EXE_stall,  MEM_stall,  WB_stall;
    wire         FCH_valid,  DCD_valid,  EXE_valid,  MEM_valid,  WB_valid; 

    // Hazard signals
    wire         load_use_stall, imem_stall, dmem_stall, branch_taken;

    // Register File Signals
    wire [4:0]  rs1_idx,  rs2_idx,  rd_idx;
    wire [63:0] rs1_data, rs2_data, rd_data;
    wire        rd_wr_en;

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
    wire        EXE_pc_target_sel;
    wire [63:0] EXE_pc_target_addr; 
    wire [63:0] FCH_pc,    FCH_next_pc;


    fetch_stage FCH 
    (
        //======= Clocks, Resets, and Stage Controls ========//
        .clk_i,
        .rst_ni,

        .squash_i       (FCH_squash),
        .stall_i        (FCH_stall),

        //============== Branch Control Inputs ==============//
        .target_sel_i   (EXE_pc_target_sel),
        .target_addr_i  (EXE_pc_target_addr),
    
        //========== Instruction Memory Interface ===========//
        .imem_req_o,
        .imem_gnt_i,
        .imem_addr_o,
        .imem_we_o,
        .imem_be_o,
        .imem_wdata_o,
        .imem_rvalid_i,

        .imem_stall_ao  (imem_stall),

        //================ Pipeline Outputs =================//
        .valid_o        (FCH_valid),
        .pc_o           (FCH_pc),
        .next_pc_o      (FCH_next_pc)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                            Decode                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    // Register File Signals
    wire [4:0]  DCD_rs1_idx,  DCD_rs2_idx,  DCD_rd_idx;
    wire        DCD_rs1_used, DCD_rs2_used, DCD_rd_wr_en;
    wire [63:0] DCD_rs1_data, DCD_rs2_data;
    wire [2:0]  DCD_rd_wr_src_1h;
    // ALU Signals
    wire [15:0] DCD_alu_op_1h;
    wire [63:0] DCD_alu_op_a,       DCD_alu_op_b;
    wire        DCD_alu_uses_rs1,   DCD_alu_uses_rs2;
    // Memory Signals
    wire [3:0]  DCD_mem_width_1h;
    wire        DCD_mem_rd,   DCD_mem_wr,   DCD_mem_sign;
    // Flow Control Signals
    wire        DCD_pc_src;
    wire [63:0] DCD_next_pc;
    wire [5:0]  DCD_br_cond_1h;


    decode_stage DCD 
    (
        //======= Clocks, Resets, and Stage Controls ========//
        .clk_i,
        .rst_ni,
        
        .squash_i           (DCD_squash),
        .stall_i            (DCD_stall),
        //=============== Fetch Stage Inputs ================//
        .pc_i               (FCH_pc),
        .next_pc_i          (FCH_next_pc),
        .valid_i            (FCH_valid),
        // Instruction from memory
        .inst_i             (imem_rdata_i),
        //======= Register File Async Read Interface ========//
        .rs1_idx_ao         (rs1_idx),
        .rs2_idx_ao         (rs2_idx),
        .rs1_data_i         (rs1_data),
        .rs2_data_i         (rs2_data),
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
        .alu_op_1h_o        (DCD_alu_op_1h),
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
        .pc_src_o           (DCD_pc_src),
        .next_pc_o          (DCD_next_pc),
        .br_cond_1h_o       (DCD_br_cond_1h)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           Execute                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    wire        EXE_rd_wr_en;
    wire [2:0]  EXE_rd_wr_src_1h;
    wire [63:0] EXE_alu_out,   EXE_rs2_data, EXE_rd_data;
    wire [4:0]  EXE_rd_idx;
    wire [3:0]  EXE_mem_width_1h;
    wire        EXE_rd,        EXE_wr,     EXE_sign;


    execute_stage EXE
    (
        //======= Clocks, Resets, and Stage Controls ========//
        .clk_i,
        .rst_ni,
        
        .squash_i          (EXE_squash),
        .stall_i           (EXE_stall),

        //============== Decode Stage Inputs ================//
        .valid_i           (DCD_valid),
        // Register Source 1 (rs1)
        .rs1_idx_i         (DCD_rs1_idx),
        .rs1_used_i        (DCD_rs1_used),
        .rs1_data_i        (DCD_rs1_data),
        // Register Source 2 (rs2)
        .rs2_idx_i         (DCD_rs2_idx),
        .rs2_used_i        (DCD_rs2_used),
        .rs2_data_i        (DCD_rs2_data),
        // Destination Register (rd)
        .rd_idx_i          (DCD_rd_idx),
        .rd_wr_en_i        (DCD_rd_wr_en),
        .rd_wr_src_1h_i    (DCD_rd_wr_src_1h),
        // ALU Operation and Operands
        .alu_op_1h_i       (DCD_alu_op_1h),
        .alu_op_a_i        (DCD_alu_op_a),
        .alu_op_b_i        (DCD_alu_op_b),
        .alu_uses_rs1_i    (DCD_alu_uses_rs1),
        .alu_uses_rs2_i    (DCD_alu_uses_rs2),
        // Load/Store
        .mem_width_1h_i    (DCD_mem_width_1h),
        .mem_rd_i          (DCD_mem_rd),
        .mem_wr_i          (DCD_mem_wr),
        .mem_sign_i        (DCD_mem_sign),
        // Flow Control
        .pc_src_i          (DCD_pc_src),
        .next_pc_i         (DCD_next_pc),
        .br_cond_1h_i      (DCD_br_cond_1h),

        //============= Forwarded Register Data =============//
        .MEM_rd_wr_en_i    (rd_wr_en),
        .MEM_valid_i       (WB_valid),
        .MEM_rd_idx_i      (rd_idx),
        .MEM_rd_data_i     (rd_data),

        //============== Flow Control Outputs ===============//
        .target_sel_o      (EXE_pc_target_sel),
        .target_addr_o     (EXE_pc_target_addr),

        .load_use_stall_ao (load_use_stall),

        //================ Pipeline Outputs =================//
        .valid_o           (EXE_valid),
        .alu_res_o         (EXE_alu_out),
        .rs2_data_o        (EXE_rs2_data),
        // Destination Register (rd)
        .rd_data_o         (EXE_rd_data),
        .rd_idx_o          (EXE_rd_idx),
        .rd_wr_en_o        (EXE_rd_wr_en),
        .rd_wr_src_1h_o    (EXE_rd_wr_src_1h),
        // Load/Store
        .mem_width_1h_o    (EXE_mem_width_1h),
        .mem_rd_o          (EXE_rd),
        .mem_wr_o          (EXE_wr),
        .mem_sign_o        (EXE_sign)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                            Memory                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    wire        MEM_rd_wr_en;
    wire [2:0]  MEM_rd_wr_src_1h;
    wire [3:0]  MEM_mem_width_1h;
    wire [4:0]  MEM_rd_idx;
    wire [63:0] MEM_rd_data;
    wire [2:0]  MEM_byte_addr;
    wire        MEM_sign;


    memory_stage MEM 
    (
        //======= Clocks, Resets, and Stage Controls ========//
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),

        .squash_i           (MEM_squash),
        .stall_i            (MEM_stall),

        //============== Execute Stage Inputs ===============//
        .valid_i            (EXE_valid),
        .alu_result_i       (EXE_alu_out),
        .rs2_data_i         (EXE_rs2_data),
        // Destination Register (rd)
        .rd_data_i          (EXE_rd_data),
        .rd_idx_i           (EXE_rd_idx),
        .rd_wr_en_i         (EXE_rd_wr_en),
        .rd_wr_src_1h_i     (EXE_rd_wr_src_1h),
        // Load/Store
        .mem_width_1h_i     (EXE_mem_width_1h),
        .mem_rd_i           (EXE_rd),
        .mem_wr_i           (EXE_wr),
        .mem_sign_i         (EXE_sign),
        
        //============== Data Memory Interface ==============//
        .dmem_req_o         (dmem_req_o),
        .dmem_gnt_i         (dmem_gnt_i),
        .dmem_addr_ao       (dmem_addr_o),
        .dmem_we_ao         (dmem_we_o),
        .dmem_be_ao         (dmem_be_o),
        .dmem_wdata_ao      (dmem_wdata_o),
        .dmem_rvalid_i      (dmem_rvalid_i),

        .dmem_stall_ao      (dmem_stall),
        .dmem_illegal_ao    (alert_o),

        //================ Pipeline Outputs =================//
        .valid_o            (MEM_valid),
        // Destination Register (rd)
        .rd_data_o          (MEM_rd_data),
        .rd_idx_o           (MEM_rd_idx),
        .rd_wr_en_o         (MEM_rd_wr_en),
        .rd_wr_src_1h_o     (MEM_rd_wr_src_1h),
        // Load/Store
        .mem_width_1h_o     (MEM_mem_width_1h),
        .mem_sign_o         (MEM_sign),
        .byte_addr_o        (MEM_byte_addr)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          Writeback                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    writeback_stage WB
    (
        //================= Stage Controls ==================//
        .squash_i           (WB_squash),
        .stall_i            (WB_stall),

        //============= Memory Pipeline Inputs ==============//
        .valid_i            (MEM_valid),
        // Destination Register (rd)
        .rd_data_i          (MEM_rd_data),
        .rd_idx_i           (MEM_rd_idx),
        .rd_wr_en_i         (MEM_rd_wr_en),
        .rd_wr_src_1h_i     (MEM_rd_wr_src_1h),
        // Data Memory Load Inputs
        .dmem_rdata_i,
        .mem_width_1h_i     (MEM_mem_width_1h),
        .mem_sign_i         (MEM_sign),
        .byte_addr_i        (MEM_byte_addr),

        //============= Register File Controls ==============//
        .rd_data_o          (rd_data),
        .rd_idx_o           (rd_idx),
        .rd_wr_en_o         (rd_wr_en),

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
    //                                     Hazard Management                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    assign branch_taken = (EXE_pc_target_sel == `PC_SRC_BRANCH);

    assign FCH_squash = branch_taken;
    assign FCH_stall  = imem_stall || dmem_stall || load_use_stall;

    assign DCD_squash = imem_stall || branch_taken;
    assign DCD_stall  = dmem_stall || load_use_stall;

    assign EXE_squash = load_use_stall;
    assign EXE_stall  = dmem_stall;

    assign MEM_squash = 'b0;
    assign MEM_stall  = dmem_stall;

    assign WB_squash = 'b0;
    assign WB_stall  = dmem_stall;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       Register File                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    register_file i_register_file 
    (
        .clk_i,

        .rs1_idx_i    (rs1_idx),
        .rs2_idx_i    (rs2_idx),

        .rd_idx_i     (rd_idx),
        .wr_data_i    (rd_data),
        .wr_en_i      (rd_wr_en),

        .rs1_data_ao  (rs1_data),
        .rs2_data_ao  (rs2_data) 
    );

endmodule


///////////////////////////////////////////////////////////////////////////////////////////////////
////   Copyright 2024 Peter Herrmann                                                           ////
////                                                                                           ////
////   Licensed under the Apache License, Version 2.0 (the "License");                         ////
////   you may not use this file except in compliance with the License.                        ////
////   You may obtain a copy of the License at                                                 ////
////                                                                                           ////
////       http://www.apache.org/licenses/LICENSE-2.0                                          ////
////                                                                                           ////
////   Unless required by applicable law or agreed to in writing, software                     ////
////   distributed under the License is distributed on an "AS IS" BASIS,                       ////
////   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.                ////
////   See the License for the specific language governing permissions and                     ////
////   limitations under the License.                                                          ////
///////////////////////////////////////////////////////////////////////////////////////////////////
