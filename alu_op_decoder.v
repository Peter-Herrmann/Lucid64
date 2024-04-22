///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: alu_op_decoder                                                                   //
// Description: One hot decoder for ALU operations                                               //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"

module alu_op_decoder (
    input      [4:0]   alu_op_code_i,  // ALU Codes {func7[5], func3, opcode[3]}
    input      [6:0]   opcode_i,
    output reg [15:0]  alu_op_1h_o     // 1 Hot encoded ALU operations
);
    reg [4:0] alu_op_code_masked;
    reg alu_op_arith;
    reg alu_mask_msb;


    always @ (alu_op_code_i, opcode_i) begin
        alu_op_arith = ( opcode_i == `OPCODE_OP_IMM || opcode_i == `OPCODE_OP_IMM_W ||
                         opcode_i == `OPCODE_OP     || opcode_i == `OPCODE_OP_W );

        alu_mask_msb = ( opcode_i == `OPCODE_OP_IMM || opcode_i == `OPCODE_OP_IMM_W ) && 
                       (alu_op_code_i[3:1] != 3'b101);

        if (alu_mask_msb)
            alu_op_code_masked = { 1'b0, alu_op_code_i[3:0] };
        else
            alu_op_code_masked = alu_op_code_i;

        if (alu_op_arith) begin
            case (alu_op_code_masked)
                `ALU_OP_ADD  : alu_op_1h_o = `ALU_1H_ADD;
                `ALU_OP_SLL  : alu_op_1h_o = `ALU_1H_SLL;
                `ALU_OP_SLT  : alu_op_1h_o = `ALU_1H_SLT;
                `ALU_OP_SLTU : alu_op_1h_o = `ALU_1H_SLTU;
                `ALU_OP_XOR  : alu_op_1h_o = `ALU_1H_XOR;
                `ALU_OP_SRL  : alu_op_1h_o = `ALU_1H_SRL;
                `ALU_OP_OR   : alu_op_1h_o = `ALU_1H_OR;
                `ALU_OP_AND  : alu_op_1h_o = `ALU_1H_AND;
                `ALU_OP_SUB  : alu_op_1h_o = `ALU_1H_SUB;
                `ALU_OP_SRA  : alu_op_1h_o = `ALU_1H_SRA;
                `ALU_OP_PASS : alu_op_1h_o = `ALU_1H_PASS;
                `ALU_OP_ADDW : alu_op_1h_o = `ALU_1H_ADDW;
                `ALU_OP_SLLW : alu_op_1h_o = `ALU_1H_SLLW;
                `ALU_OP_SRLW : alu_op_1h_o = `ALU_1H_SRLW;
                `ALU_OP_SUBW : alu_op_1h_o = `ALU_1H_SUBW;
                `ALU_OP_SRAW : alu_op_1h_o = `ALU_1H_SRAW;
                default      : alu_op_1h_o = 'b0;
            endcase
        end else if (opcode_i == `OPCODE_LUI) 
            alu_op_1h_o = `ALU_1H_PASS;
        else 
            alu_op_1h_o = `ALU_1H_ADD;
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
