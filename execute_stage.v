///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: execute_stage                                                                    //
// Description: Execute Stage. Contains the main dispatch and first cycle of execution (only     // 
//              cycle for single-cycle operations), as well as the bypassing for operands.       //
//              Branch conditions are detected at this stage as well.                            //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: CC-BY-NC-ND-4.0                                                      //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module execute_stage #(parameter VADDR = 39) (
    //======= Clocks, Resets, and Stage Controls ========//
    input                   clk_i,
    input                   rst_ni,
    
    input                   squash_i,
    input                   bubble_i,
    input                   stall_i,

    //============== Decode Stage Inputs ================//
    input                   valid_i,
    // Register Source 1 (rs1)
    input       [4:0]       rs1_idx_i,
    input                   rs1_used_i,
    input [`XLEN-1:0]       rs1_data_i,
    // Register Source 2 (rs2)
    input       [4:0]       rs2_idx_i,
    input                   rs2_used_i,
    input [`XLEN-1:0]       rs2_data_i,
    // Destination Register (rd)
    input       [4:0]       rd_idx_i,
    input                   rd_wr_en_i,
    input       [4:0]       rd_wr_src_1h_i,
    // ALU Operation and Operands
    input       [5:0]       alu_operation_i,
    input [`XLEN-1:0]       alu_op_a_i,
    input [`XLEN-1:0]       alu_op_b_i,
    input                   alu_uses_rs1_i,
    input                   alu_uses_rs2_i,
    // Load/Store
    input       [3:0]       mem_width_1h_i,
    input                   mem_rd_i,
    input                   mem_wr_i,
    input                   mem_sign_i,
    // Flow Control
    input                   branch_i,
    input [VADDR-1:0]       pc_i,
    input [VADDR-1:0]       next_pc_i,
    input       [5:0]       br_cond_1h_i,
    // CSR Control
    input                   csr_wr_en_i,
    input [2:0]             csr_op_1h_i,
    input [11:0]            csr_wr_addr_i,
    // Traps and Exceptions
    input                   ecall_ex_i,
    input                   ebreak_ex_i,
    input                   illegal_inst_ex_i,
    input                   mret_i,
    input                   wait_for_int_i,
    input                   fencei_i,

    //============= Forwarded Register Data =============//
    input                   MEM_rd_wr_en_i,
    input                   MEM_valid_i,
    input      [4:0]        MEM_rd_idx_i,
    input      [`XLEN-1:0]  MEM_rd_data_i,

    //================== CSR Interface ==================//
    input      [`XLEN-1:0]  csr_rdata_i,
    output reg [`XLEN-1:0]  csr_wdata_ao,
    output wire [11:0]      csr_wr_addr_ao,
    output wire             csr_wr_en_ao,

    //===============Traps and Exceptions================//
    output wire             ecall_ex_ao,
    output wire             ebreak_ex_ao,
    output wire             illegal_inst_ex_ao,
    output wire             mret_ao,
    output wire             wait_for_int_ao,
    output                  fencei_ao,
    output reg [VADDR-1:0]  pc_o,

    //============== Flow Control Outputs ===============//
    output wire             branch_o,
    output wire [VADDR-1:0] target_addr_o,

    output wire             load_use_haz_ao,
    output wire             alu_stall_o,
    output wire             mem_wr_ao,

    //================ Pipeline Outputs =================//
    output reg              valid_o,
    output reg [VADDR-1:0]  dmem_addr_o,
    output reg  [`XLEN-1:0] rs2_data_o,
    // Destination Register (rd)
    output reg  [`XLEN-1:0] rd_data_o,
    output reg  [4:0]       rd_idx_o,
    output reg              rd_wr_en_o,
    output reg              rd_wr_src_load_o,
    // Load/Store
    output reg  [3:0]       mem_width_1h_o,
    output reg              mem_rd_o,
    output reg              mem_wr_o,
    output reg              mem_sign_o
    );
    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Validity Tracker                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire valid;

    validity_tracker EXE_validity_tracker (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),

        .valid_i        (valid_i),
        
        .squash_i       (squash_i),
        .bubble_i       (bubble_i),
        .stall_i        (stall_i),

        .valid_ao       (valid)
    );

    assign mem_wr_ao = valid && mem_wr_i;
    
    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       Bypass Units                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [`XLEN-1:0] alu_op_a,   alu_op_b,   rs1_data,  rs2_data;
    wire             rs1_lu_haz, rs2_lu_haz;

    bypass_unit rs1_bypass_unit (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .stall_i            (stall_i),
        .bubble_i           (bubble_i),

        .EXE_mem_read_i     (mem_rd_o),
        .EXE_rd_wr_en_i     (rd_wr_en_o),
        .EXE_valid_i        (valid_o),
        .EXE_rd_idx_i       (rd_idx_o),
        .EXE_rd_data_i      (rd_data_o),

        .MEM_rd_wr_en_i     (MEM_rd_wr_en_i),
        .MEM_valid_i        (MEM_valid_i),
        .MEM_rd_idx_i       (MEM_rd_idx_i),
        .MEM_rd_data_i      (MEM_rd_data_i),

        .rs_idx_i           (rs1_idx_i),
        .rs_data_i          (rs1_data_i),
        .rs_used_i          (rs1_used_i),

        .rs_data_ao         (rs1_data),
        .load_use_hazard_ao (rs1_lu_haz)
    );

    bypass_unit rs2_bypass_unit (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .stall_i            (stall_i),
        .bubble_i           (bubble_i),

        .EXE_mem_read_i     (mem_rd_o),
        .EXE_rd_wr_en_i     (rd_wr_en_o),
        .EXE_valid_i        (valid_o),
        .EXE_rd_idx_i       (rd_idx_o),
        .EXE_rd_data_i      (rd_data_o),

        .MEM_rd_wr_en_i     (MEM_rd_wr_en_i),
        .MEM_valid_i        (MEM_valid_i),
        .MEM_rd_idx_i       (MEM_rd_idx_i),
        .MEM_rd_data_i      (MEM_rd_data_i),

        .rs_idx_i           (rs2_idx_i),
        .rs_data_i          (rs2_data_i),
        .rs_used_i          (rs2_used_i),

        .rs_data_ao         (rs2_data),
        .load_use_hazard_ao (rs2_lu_haz)
    );
    
    assign load_use_haz_ao = (rs1_lu_haz || rs2_lu_haz);

    assign alu_op_a = (alu_uses_rs1_i) ? rs1_data : alu_op_a_i;
    assign alu_op_b = (alu_uses_rs2_i) ? rs2_data : alu_op_b_i;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        CSR Controls                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(*) begin : csr_alu
        case (csr_op_1h_i)
            `CSR_ALU_OP_1H_RW: csr_wdata_ao = alu_op_a;
            `CSR_ALU_OP_1H_RS: csr_wdata_ao = csr_rdata_i | alu_op_a;
            `CSR_ALU_OP_1H_RC: csr_wdata_ao = csr_rdata_i & ~alu_op_a;
            default          : csr_wdata_ao = 'b0;
        endcase
    end

    assign csr_wr_en_ao   = csr_wr_en_i;
    assign csr_wr_addr_ao = csr_wr_addr_i;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     Execution Unit(s)                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [`XLEN-1:0] I_alu_res, M_alu_res;
    reg  [`XLEN-1:0] rd_data;
    wire             rd_wr_src_load;

    I_alu i_I_alu 
    (
        .a_i             (alu_op_a),
        .b_i             (alu_op_b),
        .alu_operation_i (alu_operation_i),

        .alu_result_oa   (I_alu_res)
    );

    M_alu i_M_alu 
    (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),

        .a_i             (alu_op_a),
        .b_i             (alu_op_b),
        .alu_operation_i (alu_operation_i),

        .alu_result_oa   (M_alu_res),
        .stall_o         (alu_stall_o)
    );

    // For forwarding only - loads (mem -> rd) are stalled
    always @(*) begin
        case (rd_wr_src_1h_i)
            `WB_SRC_1H_I_ALU     : rd_data = I_alu_res;
            `WB_SRC_1H_M_ALU     : rd_data = M_alu_res;
            `WB_SRC_1H_PC_PLUS_4 : rd_data = {{`XLEN-VADDR{1'b0}}, next_pc_i};
            `WB_SRC_CSR          : rd_data = csr_rdata_i;
            default              : rd_data = 'b0;
        endcase
    end

    assign rd_wr_src_load = (rd_wr_src_1h_i == `WB_SRC_1H_MEM);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        Flow Control                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Branch Condition Generator
    wire eq, lt, ltu;
    reg  branch_taken;

    assign eq  = (rs1_data == rs2_data);
    assign ltu = (rs1_data  < rs2_data);
    assign lt  = ( $signed(rs1_data) < $signed(rs2_data) );

    always @ (*) begin
        case (br_cond_1h_i)
            `BR_OP_1H_BEQ  : branch_taken =  eq;    
            `BR_OP_1H_BNE  : branch_taken = ~eq;
            `BR_OP_1H_BLT  : branch_taken =  lt;
            `BR_OP_1H_BGE  : branch_taken = ~lt;
            `BR_OP_1H_BLTU : branch_taken =  ltu;    
            `BR_OP_1H_BGEU : branch_taken = ~ltu;
            default        : branch_taken = 'b0;
        endcase
    end

    // Program Counter Signals
    assign branch_o      = valid && ( branch_i || branch_taken || fencei_ao);
    assign target_addr_o = fencei_ao ? next_pc_i : I_alu_res[VADDR-1:0];


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    Traps and Exceptions                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    
    wire exception;

    assign ecall_ex_ao        = valid && ecall_ex_i;
    assign ebreak_ex_ao       = valid && ebreak_ex_i;
    assign illegal_inst_ex_ao = valid && illegal_inst_ex_i;
    assign mret_ao            = valid && mret_i;
    assign wait_for_int_ao    = valid && wait_for_int_i;
    assign fencei_ao          = valid && fencei_i;

    assign exception          = ecall_ex_i || ebreak_ex_i || illegal_inst_ex_i;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //        ____  _            _ _              ____            _     _                        //
    //       |  _ \(_)_ __   ___| (_)_ __   ___  |  _ \ ___  __ _(_)___| |_ ___ _ __ ___         //
    //       | |_) | | '_ \ / _ \ | | '_ \ / _ \ | |_) / _ \/ _` | / __| __/ _ \ '__/ __|        //
    //       |  __/| | |_) |  __/ | | | | |  __/ |  _ <  __/ (_| | \__ \ ||  __/ |  \__ \        //
    //       |_|   |_| .__/ \___|_|_|_| |_|\___| |_| \_\___|\__, |_|___/\__\___|_|  |___/        //
    //               |_|                                    |___/                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk_i) begin : execute_pipeline_registers
    // On stall, all outputs do not change.
        valid_o          <= (stall_i) ? valid_o          : valid && (~exception);
        dmem_addr_o      <= (stall_i) ? dmem_addr_o      : I_alu_res[VADDR-1:0];
        rs2_data_o       <= (stall_i) ? rs2_data_o       : rs2_data;
        // Destination Register (rd)
        rd_data_o        <= (stall_i) ? rd_data_o        : rd_data;
        rd_idx_o         <= (stall_i) ? rd_idx_o         : rd_idx_i;
        rd_wr_en_o       <= (stall_i) ? rd_wr_en_o       : (rd_wr_en_i && valid);
        rd_wr_src_load_o <= (stall_i) ? rd_wr_src_load_o : rd_wr_src_load;
        // Load/Store
        mem_width_1h_o   <= (stall_i) ? mem_width_1h_o   : mem_width_1h_i;
        mem_rd_o         <= (stall_i) ? mem_rd_o         : (mem_rd_i && valid);
        mem_wr_o         <= (stall_i) ? mem_wr_o         : (mem_wr_i && valid);
        mem_sign_o       <= (stall_i) ? mem_sign_o       : mem_sign_i;
        // Program counter 
        pc_o             <= (stall_i) ? pc_o             : pc_i;
    end

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
