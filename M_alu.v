    ///////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                               //
    // Module Name: M_alu                                                                            //
    // Description: Arithmetic and Logic Unit (ALU) for the M extension (integer multiplication and  //
    //              division) of a RV64I processor.                                                  //
    // Author     : Peter Herrmann                                                                   //
    //                                                                                               //
    // SPDX-License-Identifier: Apache-2.0                                                           //
    //                                                                                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////////
    `include "Lucid64.vh"


    module M_alu (
        input                   clk_i,
        input                   rst_ni,

        input  [`XLEN-1:0]      a_i,
        input  [`XLEN-1:0]      b_i,

        input  [5:0]            alu_operation_i,

        output reg [`XLEN-1:0]  alu_result_oa,
        output wire             stall_o
    );
    // TODO - multiplier must be pipelined, then the pre and post processing steps should be 
    //        pipelined.

        ///////////////////////////////////////////////////////////////////////////////////////////////
        //                                    M-ALU Preprocessing                                    //
        ///////////////////////////////////////////////////////////////////////////////////////////////
        reg [63:0] op_a, op_b;

        // 64 bit operands
        wire a_neg        = a_i[63];
        wire b_neg        = b_i[63];
        wire res_sign     = a_neg ^ b_neg;
        wire [63:0] abs_a = a_neg ? ~a_i + 1 : a_i;
        wire [63:0] abs_b = b_neg ? ~b_i + 1 : b_i;

        // 32 bit operands
        wire a32_neg        = a_i[31];
        wire b32_neg        = b_i[31];
        wire res32_sign     = a32_neg ^ b32_neg;
        wire [31:0] abs_a32 = a32_neg ? ~a_i[31:0] + 32'b1 : a_i[31:0];
        wire [31:0] abs_b32 = b32_neg ? ~b_i[31:0] + 32'b1 : b_i[31:0];

        always @(*) begin
            case (alu_operation_i)
                `ALU_OP_MULH,  `ALU_OP_MULHSU,
                `ALU_OP_DIV,   `ALU_OP_REM      : op_a = abs_a;
                `ALU_OP_DIVW,  `ALU_OP_REMW     : op_a = { 32'b0, abs_a32[31:0] };
                `ALU_OP_DIVUW, `ALU_OP_REMUW    : op_a = { 32'b0, a_i[31:0] };
                default                         : op_a = a_i;
            endcase

            case (alu_operation_i)
                `ALU_OP_MULH, `ALU_OP_DIV, 
                `ALU_OP_REM                     : op_b = abs_b;
                `ALU_OP_DIVW,  `ALU_OP_REMW     : op_b = { 32'b0, abs_b32[31:0] };
                `ALU_OP_DIVUW, `ALU_OP_REMUW    : op_b = { 32'b0, b_i[31:0] };
                default                         : op_b = b_i;
            endcase
            
        end

        wire div_alu_req = ( (alu_operation_i == `ALU_OP_DIV)     || 
                             (alu_operation_i == `ALU_OP_DIVW)    || 
                             (alu_operation_i == `ALU_OP_DIVU)    || 
                             (alu_operation_i == `ALU_OP_DIVUW)   || 
                             (alu_operation_i == `ALU_OP_REM)     || 
                             (alu_operation_i == `ALU_OP_REMW)    || 
                             (alu_operation_i == `ALU_OP_REMU)    || 
                             (alu_operation_i == `ALU_OP_REMUW))  && 
                             (op_b != 'b0);


        ///////////////////////////////////////////////////////////////////////////////////////////////
        //                                           M-ALU                                           //
        ///////////////////////////////////////////////////////////////////////////////////////////////
        wire [127:0] product_u;
        wire [63:0]  quotient_raw, remainder_raw, quotient_u, remainder_u;
        wire         div_done;

        reg div_in_progress;

        always @(posedge clk_i) begin
            if (~rst_ni || div_done)
                div_in_progress <= 'b0;
            else if (div_alu_req)
                div_in_progress <= 'b1;
        end

        divider u_divider(
            .clk_i  (clk_i),
            .rst_ni (rst_ni),

            .op_a_i (op_a),
            .op_b_i (op_b),
            .req_i  (div_alu_req && ~div_in_progress),

            .quotient_o (quotient_raw),
            .remainder_o (remainder_raw),
            .done_o (div_done)
        );

        assign product_u   = op_a * op_b; // TODO - pipeline multiplier
        assign quotient_u  = (op_b == 'b0) ? `NEGATIVE_1 : quotient_raw;
        assign remainder_u = (op_b == 'b0) ? op_a        : remainder_raw;

        assign stall_o = (div_in_progress && ~div_done) || 
                         (div_alu_req     && ~div_done  && ~div_in_progress);


        ///////////////////////////////////////////////////////////////////////////////////////////////
        //                                   M-ALU Post Processing                                   //
        ///////////////////////////////////////////////////////////////////////////////////////////////
        reg [63:0]  div_res_a,  quotient_neg, remainder_neg;
        reg [127:0] product_su, mul_res_a,    product_neg;
        reg         carry_su;

        always @(*) begin
            // Post-process Products
            product_neg   = ~product_u + 1;
            carry_su      = (product_u[63:0] == 64'b0);
            product_su    = a_neg ? ( ~product_u + {127'b0, carry_su} ) : product_u;

            // Post Process quotient and remainder
            quotient_neg  = (op_b == 'b0) ? `NEGATIVE_1 : ~quotient_u  + 1;
            remainder_neg = ~remainder_u + 1;

            case (alu_operation_i)
                `ALU_OP_MULH    : mul_res_a = res_sign ? product_neg : product_u;
                `ALU_OP_MULHSU  : mul_res_a = product_su;
                default         : mul_res_a = product_u;
            endcase

            case (alu_operation_i)
                `ALU_OP_DIV   : div_res_a  = res_sign ? quotient_neg  : quotient_u;
                `ALU_OP_REM   : div_res_a  = a_neg    ? remainder_neg : remainder_u;
                `ALU_OP_DIVU  : div_res_a  = quotient_u;
                `ALU_OP_REMU  : div_res_a  = remainder_u;
                `ALU_OP_DIVW  : div_res_a  = res32_sign ? quotient_neg  : quotient_u;
                `ALU_OP_REMW  : div_res_a  = a32_neg    ? remainder_neg : remainder_u;
                `ALU_OP_DIVUW : div_res_a  = quotient_u;
                `ALU_OP_REMUW : div_res_a  = remainder_u;
                default                     : div_res_a  = 'b0;
            endcase

            case (alu_operation_i)
                `ALU_OP_MUL     : alu_result_oa = mul_res_a[`XLEN-1:0];
                `ALU_OP_MULH    : alu_result_oa = mul_res_a[((2*`XLEN)-1):`XLEN];
                `ALU_OP_MULHSU  : alu_result_oa = mul_res_a[((2*`XLEN)-1):`XLEN];
                `ALU_OP_MULHU   : alu_result_oa = mul_res_a[((2*`XLEN)-1):`XLEN];
                `ALU_OP_MULW    : alu_result_oa = { {32{mul_res_a[31]}}, mul_res_a[31:0] };
                `ALU_OP_DIV     : alu_result_oa = div_res_a;
                `ALU_OP_DIVU    : alu_result_oa = div_res_a;
                `ALU_OP_REM     : alu_result_oa = div_res_a;
                `ALU_OP_REMU    : alu_result_oa = div_res_a;
                default         : alu_result_oa = { {32{div_res_a[31]}}, div_res_a[31:0] };
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
