///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: alu_src_decoder                                                                  //
// Description: ALU MUX select decoders                                                          //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"

module alu_src_decoder (
    input      [6:0] opcode_i,
    output reg [1:0] alu_a_src_o, alu_b_src_o
);

    always @(opcode_i) begin
        case (opcode_i)
            `OPCODE_LUI     : alu_a_src_o = `ALU_A_SRC_U_IMMED;
            `OPCODE_AUIPC   : alu_a_src_o = `ALU_A_SRC_U_IMMED;
            `OPCODE_JAL     : alu_a_src_o = `ALU_A_SRC_J_IMMED;
            `OPCODE_BRANCH  : alu_a_src_o = `ALU_A_SRC_B_IMMED;
            default         : alu_a_src_o = `ALU_A_SRC_RS1;
        endcase

        case (opcode_i)
            `OPCODE_AUIPC   : alu_b_src_o = `ALU_B_SRC_PC;
            `OPCODE_JAL     : alu_b_src_o = `ALU_B_SRC_PC;
            `OPCODE_BRANCH  : alu_b_src_o = `ALU_B_SRC_PC;
            `OPCODE_STORE   : alu_b_src_o = `ALU_B_SRC_S_IMMED;
            `OPCODE_LOAD    : alu_b_src_o = `ALU_B_SRC_I_IMMED;
            `OPCODE_JALR    : alu_b_src_o = `ALU_B_SRC_I_IMMED;
            `OPCODE_OP_IMM  : alu_b_src_o = `ALU_B_SRC_I_IMMED; 
            `OPCODE_OP_IMM_W: alu_b_src_o = `ALU_B_SRC_I_IMMED; 
            default         : alu_b_src_o = `ALU_B_SRC_RS2;
        endcase
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
