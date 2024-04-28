///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: decode_stage                                                                     //
// Description: Decode Stage. A single-instruction synchronous decoder. Several options are      //
//              1-hot.                                                                           //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module decode_stage (
    //======= Clocks, Resets, and Stage Controls ========//
    input               clk_i,
    input               rst_ni,
    
    input               squash_i,
    input               bubble_i,
    input               stall_i,

    //=============== Fetch Stage Inputs ================//
    input       [63:0]  pc_i,
    input       [63:0]  next_pc_i,
    input               valid_i,
    // Instruction from memory
    input       [31:0]  inst_i,

    //======= Register File Async Read Interface ========//
    output wire [4:0]   rs1_idx_ao,
    output wire [4:0]   rs2_idx_ao,
    input       [63:0]  rs1_data_i,
    input       [63:0]  rs2_data_i,

    //================ Pipeline Outputs =================//
    output reg          valid_o,
    // Register Source 1 (rs1)
    output reg  [4:0]   rs1_idx_o,
    output reg          rs1_used_o,
    output reg  [63:0]  rs1_data_o,
    // Register Source 2 (rs2)
    output reg  [4:0]   rs2_idx_o,
    output reg          rs2_used_o,
    output reg  [63:0]  rs2_data_o,
    // Destination Register (rd)
    output reg  [4:0]   rd_idx_o,
    output reg          rd_wr_en_o,
    output reg  [2:0]   rd_wr_src_1h_o,
    // ALU Operation and Operands
    output reg  [15:0]  alu_op_1h_o,
    output reg  [63:0]  alu_op_a_o,
    output reg  [63:0]  alu_op_b_o,
    output reg          alu_uses_rs1_o,
    output reg          alu_uses_rs2_o,
    // Load/Store
    output reg  [3:0]   mem_width_1h_o,
    output reg          mem_rd_o,
    output reg          mem_wr_o,
    output reg          mem_sign_o,
    // Flow Control
    output reg          pc_src_o,
    output reg  [63:0]  next_pc_o,
    output reg  [5:0]   br_cond_1h_o
);

    wire [2:0]  func3       = inst_i[14:12];
    wire [6:0]  opcode      = inst_i[6:0];
    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Validity Tracker                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire valid;

    validity_tracker DCD_validity_tracker (
        .clk_i,
        .rst_ni,

        .valid_i,
        
        .squash_i,
        .bubble_i,
        .stall_i,

        .valid_ao       (valid)
    );

    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Load Store Signals                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    
    reg  [3:0]  mem_width_1h;
    wire [1:0]  mem_width    = func3[1:0];
    wire        mem_sign     = func3[2];
    wire        mem_wr       = (opcode == `OPCODE_STORE);
    wire        mem_rd       = (opcode == `OPCODE_LOAD);

    always @(mem_width) begin
        case (mem_width)
            `MEM_WIDTH_BYTE     : mem_width_1h = `MEM_WIDTH_1H_BYTE;
            `MEM_WIDTH_HALF     : mem_width_1h = `MEM_WIDTH_1H_HALF;
            `MEM_WIDTH_WORD     : mem_width_1h = `MEM_WIDTH_1H_WORD;
            `MEM_WIDTH_DOUBLE   : mem_width_1h = `MEM_WIDTH_1H_DOUBLE;
            default             : mem_width_1h = 'b0;
        endcase
    end

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          Register File                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire rs1_used, rs2_used, rd_wr_en;
    wire [4:0] rs1_idx = inst_i[19:15];
    wire [4:0] rs2_idx = inst_i[24:20];
    wire [4:0] rd_idx  = inst_i[11:7];
    reg  [2:0] rd_wr_src_1h;

    assign rs1_used = (opcode != `OPCODE_LUI)   && 
                      (opcode != `OPCODE_AUIPC) && 
                      (opcode != `OPCODE_JAL);

    assign rs2_used = (opcode == `OPCODE_BRANCH) || 
                      (opcode == `OPCODE_STORE)  || 
                      (opcode == `OPCODE_OP_W)   ||
                      (opcode == `OPCODE_OP);

    assign rd_wr_en = (opcode != `OPCODE_BRANCH) && 
                      (opcode != `OPCODE_STORE)  && 
                      (opcode != `OPCODE_SYSTEM) &&
                      (rd_idx != 'b0); 

    always @(opcode) begin : rd_wr_src_decoder
        case (opcode)
            `OPCODE_JAL  : rd_wr_src_1h = `WB_SRC_1H_PC_PLUS_4; 
            `OPCODE_JALR : rd_wr_src_1h = `WB_SRC_1H_PC_PLUS_4;
            `OPCODE_LOAD : rd_wr_src_1h = `WB_SRC_1H_MEM;
            default      : rd_wr_src_1h = `WB_SRC_1H_ALU; 
        endcase
    end
    
    assign rs1_idx_ao = rs1_idx;
    assign rs2_idx_ao = rs2_idx;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Immediate Generator                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [63:0] i_immed, s_immed, b_immed, u_immed, j_immed;

    immediate_gen i_immed_gen (
        .inst_31_7_i    (inst_i[31:7]),
        
        .i_immed_o      (i_immed),
        .s_immed_o      (s_immed),
        .b_immed_o      (b_immed),
        .u_immed_o      (u_immed),
        .j_immed_o      (j_immed)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ALU Operation                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [15:0] alu_op_1h;
    reg  [63:0] alu_op_a,  alu_op_b;
    wire [1:0]  alu_a_src, alu_b_src;

    alu_op_decoder i_alu_op_decoder (
        .alu_op_code_i   ( { inst_i[30], func3, opcode[3] } ),
        .opcode_i        (opcode),
        .alu_op_1h_o     (alu_op_1h)
    );

    alu_src_decoder i_alu_src_decoder (
        .opcode_i        (opcode),
        .alu_a_src_o     (alu_a_src), 
        .alu_b_src_o     (alu_b_src)
    );

    always @(*) begin : alu_op_a_mux
        case(alu_a_src)
            `ALU_A_SRC_U_IMMED  : alu_op_a = u_immed;
            `ALU_A_SRC_J_IMMED  : alu_op_a = j_immed;
            `ALU_A_SRC_B_IMMED  : alu_op_a = b_immed;
            default             : alu_op_a = rs1_data_i;
        endcase
    end

    always @(*) begin : alu_op_b_mux
        case(alu_b_src)
            `ALU_B_SRC_I_IMMED  : alu_op_b = i_immed;
            `ALU_B_SRC_S_IMMED  : alu_op_b = s_immed;
            `ALU_B_SRC_PC       : alu_op_b = pc_i;
            default             : alu_op_b = rs2_data_i;
        endcase
    end

    wire alu_uses_rs1 = (alu_a_src == `ALU_A_SRC_RS1);
    wire alu_uses_rs2 = (alu_b_src == `ALU_B_SRC_RS2);


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          Flow Control                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg  [5:0] branch_cond_1h;
    wire pc_src;

    always @(opcode, func3) begin
        if (opcode == `OPCODE_BRANCH) begin
            case (func3)
                `BR_OP_BEQ  : branch_cond_1h = `BR_OP_1H_BEQ;     
                `BR_OP_BNE  : branch_cond_1h = `BR_OP_1H_BNE; 
                `BR_OP_BLT  : branch_cond_1h = `BR_OP_1H_BLT; 
                `BR_OP_BGE  : branch_cond_1h = `BR_OP_1H_BGE; 
                `BR_OP_BLTU : branch_cond_1h = `BR_OP_1H_BLTU; 
                `BR_OP_BGEU : branch_cond_1h = `BR_OP_1H_BGEU;     
                default     : branch_cond_1h = 'b0;
            endcase
        end else begin
                              branch_cond_1h = 'b0;
        end
    end

    assign pc_src = (opcode == `OPCODE_JAL || 
                     opcode == `OPCODE_JALR) 
                    ? `PC_SRC_BRANCH : `PC_SRC_NO_BRANCH;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //        ____  _            _ _              ____            _     _                        //
    //       |  _ \(_)_ __   ___| (_)_ __   ___  |  _ \ ___  __ _(_)___| |_ ___ _ __ ___         //
    //       | |_) | | '_ \ / _ \ | | '_ \ / _ \ | |_) / _ \/ _` | / __| __/ _ \ '__/ __|        //
    //       |  __/| | |_) |  __/ | | | | |  __/ |  _ <  __/ (_| | \__ \ ||  __/ |  \__ \        //
    //       |_|   |_| .__/ \___|_|_|_| |_|\___| |_| \_\___|\__, |_|___/\__\___|_|  |___/        //
    //               |_|                                    |___/                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk_i) begin : decode_pipeline_registers
    // On reset, all signals set to 0; on stall, all outputs do not change.
        valid_o         <= ~rst_ni ? 'b0 : (stall_i ? valid_o        : valid);
        // Register Source 1 (rs1)
        rs1_idx_o       <= ~rst_ni ? 'b0 : (stall_i ? rs1_idx_o      : (rs1_used ? rs1_idx : 'b0));
        rs1_used_o      <= ~rst_ni ? 'b0 : (stall_i ? rs1_used_o     : rs1_used);
        rs1_data_o      <= ~rst_ni ? 'b0 : (stall_i ? rs1_data_o     : rs1_data_i);
        // Register Source 2 (rs2)
        rs2_idx_o       <= ~rst_ni ? 'b0 : (stall_i ? rs2_idx_o      : (rs2_used ? rs2_idx : 'b0));
        rs2_used_o      <= ~rst_ni ? 'b0 : (stall_i ? rs2_used_o     : rs2_used);
        rs2_data_o      <= ~rst_ni ? 'b0 : (stall_i ? rs2_data_o     : rs2_data_i);
        // Destination Register (rd)
        rd_idx_o        <= ~rst_ni ? 'b0 : (stall_i ? rd_idx_o       : rd_idx);
        rd_wr_en_o      <= ~rst_ni ? 'b0 : (stall_i ? rd_wr_en_o     : rd_wr_en);
        rd_wr_src_1h_o  <= ~rst_ni ? 'b0 : (stall_i ? rd_wr_src_1h_o : rd_wr_src_1h);
        // ALU Operation and Operands
        alu_op_1h_o     <= ~rst_ni ? 'b0 : (stall_i ? alu_op_1h_o    : alu_op_1h);
        alu_op_a_o      <= ~rst_ni ? 'b0 : (stall_i ? alu_op_a_o     : alu_op_a);
        alu_op_b_o      <= ~rst_ni ? 'b0 : (stall_i ? alu_op_b_o     : alu_op_b);
        alu_uses_rs1_o  <= ~rst_ni ? 'b0 : (stall_i ? alu_uses_rs1_o : alu_uses_rs1);
        alu_uses_rs2_o  <= ~rst_ni ? 'b0 : (stall_i ? alu_uses_rs2_o : alu_uses_rs2);
        // Load/Store
        mem_width_1h_o  <= ~rst_ni ? 'b0 : (stall_i ? mem_width_1h_o : mem_width_1h);
        mem_rd_o        <= ~rst_ni ? 'b0 : (stall_i ? mem_rd_o       : mem_rd);
        mem_wr_o        <= ~rst_ni ? 'b0 : (stall_i ? mem_wr_o       : mem_wr);
        mem_sign_o      <= ~rst_ni ? 'b0 : (stall_i ? mem_sign_o     : mem_sign);
        // Flow Control
        pc_src_o        <= ~rst_ni ? 'b0 : (stall_i ? pc_src_o       : pc_src);
        next_pc_o       <= ~rst_ni ? 'b0 : (stall_i ? next_pc_o      : next_pc_i);
        br_cond_1h_o    <= ~rst_ni ? 'b0 : (stall_i ? br_cond_1h_o   : branch_cond_1h); 
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
