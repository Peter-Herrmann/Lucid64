///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: I_alu                                                                            //
// Description: RV64I Arithmetic and Logic Unit.                                                 //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module I_alu (
    input      [`XLEN-1:0] a_i,
    input      [`XLEN-1:0] b_i,
    input      [5:0]       alu_operation_i,

    output reg [`XLEN-1:0] alu_result_oa
);

    wire [31:0] a_32 = a_i[31:0];
    wire [31:0] b_32 = b_i[31:0];

    wire [31:0] addw_res = a_32  + b_32;
    wire [31:0] sllw_res = a_32 << b_32[4:0];
    wire [31:0] srlw_res = a_32 >> b_32[4:0];
    wire [31:0] subw_res = a_32  - b_32;
    wire [31:0] sraw_res = $signed(a_32) >>> b_32[4:0];


    always @ (*) begin
        case (alu_operation_i)
            `ALU_OP_ADD  : alu_result_oa = a_i + b_i;
            `ALU_OP_SLL  : alu_result_oa = a_i << b_i[5:0];
            `ALU_OP_SLT  : alu_result_oa = $signed(a_i) < $signed(b_i) ? 64'd1: 'b0;
            `ALU_OP_SLTU : alu_result_oa = a_i < b_i ? 64'd1: 'b0;
            `ALU_OP_XOR  : alu_result_oa = a_i ^ b_i;
            `ALU_OP_SRL  : alu_result_oa = a_i >> b_i[5:0];
            `ALU_OP_OR   : alu_result_oa = a_i | b_i;
            `ALU_OP_AND  : alu_result_oa = a_i & b_i;
            `ALU_OP_SUB  : alu_result_oa = a_i - b_i;
            `ALU_OP_SRA  : alu_result_oa = $signed(a_i) >>> b_i[5:0];
            `ALU_OP_PASS : alu_result_oa = a_i;

            // RV64I W (32 bit) opcodes
            `ALU_OP_ADDW : alu_result_oa = { {32{addw_res[31]}}, addw_res };
            `ALU_OP_SLLW : alu_result_oa = { {32{sllw_res[31]}}, sllw_res };
            `ALU_OP_SRLW : alu_result_oa = { {32{srlw_res[31]}}, srlw_res };
            `ALU_OP_SUBW : alu_result_oa = { {32{subw_res[31]}}, subw_res };
            `ALU_OP_SRAW : alu_result_oa = { {32{sraw_res[31]}}, sraw_res };
            default           : alu_result_oa = 'b0; 
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
