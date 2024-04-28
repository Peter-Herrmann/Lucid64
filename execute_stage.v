///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: execute_stage                                                                    //
// Description: Execute Stage. Contains the main dispatch and first cycle of execution (only     // 
//              cycle for single-cycle operations), as well as the bypassing for operands.       //
//              Branch conditions are detected at this stage as well.                            //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module execute_stage (
    //======= Clocks, Resets, and Stage Controls ========//
    input               clk_i,
    input               rst_ni,
    
    input               squash_i,
    input               bubble_i,
    input               stall_i,

    //============== Decode Stage Inputs ================//
    input               valid_i,
    // Register Source 1 (rs1)
    input       [4:0]   rs1_idx_i,
    input               rs1_used_i,
    input       [63:0]  rs1_data_i,
    // Register Source 2 (rs2)
    input       [4:0]   rs2_idx_i,
    input               rs2_used_i,
    input       [63:0]  rs2_data_i,
    // Destination Register (rd)
    input       [4:0]   rd_idx_i,
    input               rd_wr_en_i,
    input       [2:0]   rd_wr_src_1h_i,
    // ALU Operation and Operands
    input       [15:0]  alu_op_1h_i,
    input       [63:0]  alu_op_a_i,
    input       [63:0]  alu_op_b_i,
    input               alu_uses_rs1_i,
    input               alu_uses_rs2_i,
    // Load/Store
    input       [3:0]   mem_width_1h_i,
    input               mem_rd_i,
    input               mem_wr_i,
    input               mem_sign_i,
    // Flow Control
    input               pc_src_i,
    input       [63:0]  next_pc_i,
    input       [5:0]   br_cond_1h_i,

    //============= Forwarded Register Data =============//
    input               MEM_rd_wr_en_i,
    input               MEM_valid_i,
    input      [4:0]    MEM_rd_idx_i,
    input      [63:0]   MEM_rd_data_i,

    //============== Flow Control Outputs ===============//
    output wire         target_sel_o,
    output wire [63:0]  target_addr_o,

    output wire         load_use_stall_ao,

    //================ Pipeline Outputs =================//
    output reg          valid_o,
    output reg [63:0]   alu_res_o,
    output reg  [63:0]  rs2_data_o,
    // Destination Register (rd)
    output reg  [63:0]  rd_data_o,
    output reg  [4:0]   rd_idx_o,
    output reg          rd_wr_en_o,
    output reg  [2:0]   rd_wr_src_1h_o,
    // Load/Store
    output reg  [3:0]   mem_width_1h_o,
    output reg          mem_rd_o,
    output reg          mem_wr_o,
    output reg          mem_sign_o
);
    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Validity Tracker                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg  squashed_during_stall, squashed_during_bubble;

    always @(posedge clk_i) begin
        if (~rst_ni || ~stall_i) 
            squashed_during_stall   <= 'b0;
        else if (stall_i && squash_i) 
            squashed_during_stall   <= 'b1;
    end

    always @(posedge clk_i) begin
        if (~rst_ni || ~bubble_i) 
            squashed_during_bubble   <= 'b0;
        else if (bubble_i && squash_i) 
            squashed_during_bubble   <= 'b1;
    end

    wire valid = valid_i && ~squash_i && ~squashed_during_stall && ~squashed_during_bubble;

    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       Bypass Units                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [63:0] alu_op_a, alu_op_b, rs1_data, rs2_data;
    wire        rs1_lu_haz, rs2_lu_haz;

    bypass_unit rs1_bypass_unit
    (
        .EXE_mem_read_i     (mem_rd_o),
        .EXE_rd_wr_en_i     (rd_wr_en_o),    .MEM_rd_wr_en_i,
        .EXE_valid_i        (valid_o),       .MEM_valid_i,
        .EXE_rd_idx_i       (rd_idx_o),      .MEM_rd_idx_i,
        .EXE_rd_data_i      (rd_data_o),     .MEM_rd_data_i,

        .rs_idx_i           (rs1_idx_i),
        .rs_data_i          (rs1_data_i),
        .rs_used_i          (rs1_used_i),

        .rs_data_ao         (rs1_data),
        .load_use_hazard_ao (rs1_lu_haz)
    );

    bypass_unit rs2_bypass_unit
    (
        .EXE_mem_read_i     (mem_rd_o),
        .EXE_rd_wr_en_i     (rd_wr_en_o),    .MEM_rd_wr_en_i,
        .EXE_valid_i        (valid_o),       .MEM_valid_i,
        .EXE_rd_idx_i       (rd_idx_o),      .MEM_rd_idx_i,
        .EXE_rd_data_i      (rd_data_o),     .MEM_rd_data_i,

        .rs_idx_i           (rs2_idx_i),
        .rs_data_i          (rs2_data_i),
        .rs_used_i          (rs2_used_i),

        .rs_data_ao         (rs2_data),
        .load_use_hazard_ao (rs2_lu_haz)
    );
    
    assign load_use_stall_ao = (rs1_lu_haz || rs2_lu_haz);

    assign alu_op_a = (alu_uses_rs1_i) ? rs1_data : alu_op_a_i;
    assign alu_op_b = (alu_uses_rs2_i) ? rs2_data : alu_op_b_i;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     Execution Unit(s)                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [63:0] alu_res, rd_data;

    integer_alu i_alu 
    (
        .a_i            (alu_op_a),
        .b_i            (alu_op_b),
        .alu_op_1h_i    (alu_op_1h_i),

        .alu_result_oa  (alu_res)
    );

    // For forwarding only - loads (mem -> rd) are stalled
    assign rd_data = (rd_wr_src_1h_i[0]) ? alu_res : next_pc_i;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        Flow Control                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Branch Cond. Gen
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
    assign target_sel_o  = ( valid & ( pc_src_i == `PC_SRC_BRANCH || branch_taken ) )
                            ? `PC_SRC_BRANCH : `PC_SRC_NO_BRANCH;
    assign target_addr_o = alu_res;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //        ____  _            _ _              ____            _     _                        //
    //       |  _ \(_)_ __   ___| (_)_ __   ___  |  _ \ ___  __ _(_)___| |_ ___ _ __ ___         //
    //       | |_) | | '_ \ / _ \ | | '_ \ / _ \ | |_) / _ \/ _` | / __| __/ _ \ '__/ __|        //
    //       |  __/| | |_) |  __/ | | | | |  __/ |  _ <  __/ (_| | \__ \ ||  __/ |  \__ \        //
    //       |_|   |_| .__/ \___|_|_|_| |_|\___| |_| \_\___|\__, |_|___/\__\___|_|  |___/        //
    //               |_|                                    |___/                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk_i) begin : execute_pipeline_registers
    // On reset, all signals set to 0; on stall, all outputs do not change.
        valid_o         <= ~rst_ni ? 'b0 : (stall_i ? valid_o        : valid );
        alu_res_o       <= ~rst_ni ? 'b0 : (stall_i ? alu_res_o      : alu_res );
        rs2_data_o      <= ~rst_ni ? 'b0 : (stall_i ? rs2_data_o     : rs2_data);
        // Destination Register (rd)
        rd_data_o       <= ~rst_ni ? 'b0 : (stall_i ? rd_data_o      : rd_data );
        rd_idx_o        <= ~rst_ni ? 'b0 : (stall_i ? rd_idx_o       : rd_idx_i );
        rd_wr_en_o      <= ~rst_ni ? 'b0 : (stall_i ? rd_wr_en_o     : rd_wr_en_i );
        rd_wr_src_1h_o  <= ~rst_ni ? 'b0 : (stall_i ? rd_wr_src_1h_o : rd_wr_src_1h_i );
        // Load/Store
        mem_width_1h_o  <= ~rst_ni ? 'b0 : (stall_i ? mem_width_1h_o : mem_width_1h_i );
        mem_rd_o        <= ~rst_ni ? 'b0 : (stall_i ? mem_rd_o       : mem_rd_i );
        mem_wr_o        <= ~rst_ni ? 'b0 : (stall_i ? mem_wr_o       : mem_wr_i );
        mem_sign_o      <= ~rst_ni ? 'b0 : (stall_i ? mem_sign_o     : mem_sign_i );
    end

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
