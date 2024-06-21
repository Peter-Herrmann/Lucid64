///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: alu_decoder                                                                      //
// Description: This module decodes the ALU operations and operands from a 32 bit RV64IM         //
//              instruction.                                                                     //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module alu_decoder #(parameter VADDR = 39) (
    input      [31:0]       inst_i,

    input [`XLEN-1:0]       rs1_data_i,
    input [`XLEN-1:0]       rs2_data_i,

    input [VADDR-1:0]       pc_i,

    output wire [`XLEN-1:0] csr_imm_ao,

    output reg [`XLEN-1:0]  alu_op_a_ao,
    output reg [`XLEN-1:0]  alu_op_b_ao,
    output reg              alu_uses_rs1_ao,
    output reg              alu_uses_rs2_ao,

    output reg  [5:0]       alu_operation_ao
);

    wire [2:0] func3  = inst_i[14:12];
    wire [6:0] opcode = inst_i[6:0];


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Immediate Generator                                  //
    /////////////////////////////////////////////////////////////////////////////////////////////// 

    reg [`XLEN-1:0] csr_imm, i_imm, s_imm, u_imm, b_imm, j_imm;

    always @(*) begin
        csr_imm = { 59'b0, inst_i[19:15] };
        i_imm = { { 52{inst_i[31]} }, inst_i[31:20] } ;
        s_imm = { { 52{inst_i[31]} }, inst_i[31:25], inst_i[11:7]};
        u_imm = { { 32{inst_i[31]} }, inst_i[31:12], 12'b0};
        b_imm = { { 51{inst_i[31]} }, inst_i[31], inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0};
        j_imm = { { 43{inst_i[31]} }, inst_i[31], inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0};
    end

    assign csr_imm_ao = csr_imm;
    

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    ALU Operand Decoders                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire csr_op = (func3 == `SYSTEM_OP_CSRRWI) || 
                  (func3 == `SYSTEM_OP_CSRRSI) || 
                  (func3 == `SYSTEM_OP_CSRRCI);
    wire [`XLEN-1:0] pc = { {`XLEN-VADDR{1'b0}},  pc_i};

    always @(*) begin : alu_operand_decoder
        case (opcode)
            `OPCODE_LUI     : alu_op_a_ao = u_imm;
            `OPCODE_AUIPC   : alu_op_a_ao = u_imm;
            `OPCODE_JAL     : alu_op_a_ao = j_imm;
            `OPCODE_BRANCH  : alu_op_a_ao = b_imm;
            `OPCODE_SYSTEM  : alu_op_a_ao = (csr_op) ? csr_imm : rs1_data_i;
            default         : alu_op_a_ao = rs1_data_i;
        endcase

        case (opcode)
            `OPCODE_AUIPC   : alu_op_b_ao = pc;
            `OPCODE_JAL     : alu_op_b_ao = pc;
            `OPCODE_BRANCH  : alu_op_b_ao = pc;
            `OPCODE_STORE   : alu_op_b_ao = s_imm;
            `OPCODE_LOAD    : alu_op_b_ao = i_imm;
            `OPCODE_JALR    : alu_op_b_ao = i_imm;
            `OPCODE_OP_IMM  : alu_op_b_ao = i_imm; 
            `OPCODE_OP_IMM_W: alu_op_b_ao = i_imm; 
            default         : alu_op_b_ao = rs2_data_i;
        endcase
                           
        alu_uses_rs2_ao = (opcode == `OPCODE_OP_W) || (opcode == `OPCODE_OP);
        alu_uses_rs1_ao = ((opcode == `OPCODE_SYSTEM) && csr_op) ||
                          ((opcode != `OPCODE_LUI)   && 
                           (opcode != `OPCODE_AUIPC) && 
                           (opcode != `OPCODE_JAL)   &&
                           (opcode != `OPCODE_BRANCH));
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  ALU Operation Decoders                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire func7_5 = inst_i[30];
    wire func7_0 = inst_i[25];

    reg [5:0] alu_op_code;
    reg alu_op_arith, non_shift_imm, op_imm;

    always @ (*) begin
        alu_op_arith     = ( opcode == `OPCODE_OP_IMM || opcode == `OPCODE_OP_IMM_W ||
                             opcode == `OPCODE_OP     || opcode == `OPCODE_OP_W );

        // In RV64I, func7[0] is shamt[5] for shift operations, which conflicts with M codes.
        // No M codes are immediate, so func7[0] should be ignored (cleared) for all immediates
        op_imm = ( opcode == `OPCODE_OP_IMM || opcode == `OPCODE_OP_IMM_W );
        // For immediate values (except shift immediates), func7[5] is imm[10] and must be
        // ignored (cleared) when choosing ALU operation
        non_shift_imm = op_imm && (func3 != `FUNC3_ALU_SHIFT);
        alu_op_code = { (func7_5 & ~non_shift_imm), (func7_0 & ~op_imm), func3, opcode[3] };

        if      (alu_op_arith)          alu_operation_ao = alu_op_code;
        else if (opcode == `OPCODE_LUI) alu_operation_ao = `ALU_OP_PASS;
        else                            alu_operation_ao = `ALU_OP_ADD;
        
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
