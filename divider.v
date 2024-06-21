///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: divider                                                                          //
// Description: This is a configurable pipelined unsigned divider module. The parameters for the //
//              module are:                                                                      //
//              - XLEN         : The data width                                                  //
//              - STAGE_DEPTH  : How may bits of the result are calculated per pipeline stage    //
//                               A value of 0 means there is no pipelineing                      //
//              - STAGE_OFFSET : Offsets the pipeline stages, a value of 0 means the first       //
//                               stage is the full depth, while a value of 1 means the first bit //
//                               of the result will be registered.                               //
//                                                                                               //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: CC-BY-NC-ND-4.0                                                      //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////

module divider #( parameter   XLEN           = 64,
                  parameter   STAGE_DEPTH    = 5,
                  parameter   STAGE_OFFSET   = 2 )
(
    input                   clk_i,
    input                   rst_ni,

    input  [XLEN-1:0]       op_a_i,
    input  [XLEN-1:0]       op_b_i,
    input                   req_i,

    output wire [XLEN-1:0]  quotient_o,
    output wire [XLEN-1:0]  remainder_o,
    output wire             done_o
);

    // Configuration-based constants
    localparam STAGE1_IDX   = STAGE_OFFSET == 0 ? STAGE_DEPTH-1 : (STAGE_OFFSET-1) % STAGE_DEPTH;
    localparam FLOOR_STAGES = (XLEN / STAGE_DEPTH);
    localparam CEIL_STAGES  = (XLEN % STAGE_DEPTH == 0) ? 
                              (XLEN / STAGE_DEPTH) : (XLEN / STAGE_DEPTH) + 1;
    localparam NUM_STAGES   = (STAGE_DEPTH == 0) ? 0 : 
                              ( STAGE1_IDX >= (XLEN % STAGE_DEPTH) ) ? FLOOR_STAGES : CEIL_STAGES;

    // Pipeline stage and bit element declarations
    reg            valid       [NUM_STAGES:0];
    reg [XLEN-1:0] divisor     [NUM_STAGES:0];
    reg [XLEN-1:0] dividend_r  [NUM_STAGES:0];
    reg [XLEN-1:0] quotient_r  [NUM_STAGES:0];

    wire [XLEN-1:0] dividend_a  [XLEN:0] /* verilator split_var */;  
    wire [XLEN-1:0] quotient_a  [XLEN:0] /* verilator split_var */;     

    // Pipeline inputs
    always @(*) begin
        valid[0]         = ~rst_ni ? 'b0 : req_i;  
        divisor[0]       = op_b_i;
    end
  
    assign dividend_a[0] = op_a_i;
    assign quotient_a[0] = 0;   
    
    generate
    	genvar i;
    	for (i=0; i < XLEN; i = i + 1) begin
            localparam stage     = (i <= STAGE1_IDX) ? 
                                    0 : (i-STAGE1_IDX-1 + STAGE_DEPTH) / STAGE_DEPTH;
            localparam reg_stage = ((i % STAGE_DEPTH) == STAGE1_IDX) && (NUM_STAGES != 0);

            wire                partial_quotient;
            wire [i:0]          partial_remainder;
            wire [XLEN-1:0]     next_dividend;

            if (i+1 != XLEN) begin : partial_step
                // Division step (1-bit of calculation)
                wire [i:0]        upper_dividend, lower_divisor;
                wire [XLEN-1:i+1] upper_divisor,  lower_dividend;

                assign {upper_dividend, lower_dividend} = dividend_a[i];
                assign {upper_divisor,  lower_divisor}  = divisor[stage];
                
                assign partial_quotient  = !(|{upper_divisor}) && (upper_dividend >= lower_divisor);    
                assign partial_remainder = partial_quotient ? 
                                           (upper_dividend - lower_divisor) : upper_dividend;
                assign next_dividend     = {partial_remainder, lower_dividend};

            end else begin : final_step
                // Final division step (result of calculation)
                assign partial_quotient  = dividend_a[i] >= divisor[stage];
                assign partial_remainder = partial_quotient ? 
                                           (dividend_a[i] - divisor[stage]) : dividend_a[i];
                assign next_dividend     = partial_remainder;

            end

            if ( reg_stage ) begin : registered_step
                // Pipeline registers and stage logic for registered steps in a pipelined design
                always @ (posedge clk_i) begin : stage_registers
                    if (~rst_ni) begin
                        valid[stage+1]                <= 'b0;
                        divisor[stage+1]              <= 'b0;
                        dividend_r[stage+1]           <= 'b0;
                        quotient_r[stage+1]           <= 'b0;
                    end else begin
                        valid     [stage+1]           <= valid[stage];
                        divisor   [stage+1]           <= divisor[stage];
                        dividend_r[stage+1]           <= next_dividend;
                        quotient_r[stage+1]           <= quotient_a[i];
                        quotient_r[stage+1][XLEN-i-1] <= partial_quotient;
                    end
                end

                assign dividend_a[i+1] = dividend_r[stage+1];
                assign quotient_a[i+1] = quotient_r[stage+1];

            end else begin : combinational_step
                // Combinational logic for unregistered steps
                assign dividend_a[i+1]           = next_dividend;
                assign quotient_a[i+1][XLEN-i-1] = partial_quotient;

                if (i != 0) begin : quotient_not_first_step 
                    assign quotient_a[i+1][XLEN-1:XLEN-i] = quotient_a[i][XLEN-1:XLEN-i];
                end

                if (i != XLEN-1) begin : quotient_not_last_step
                    assign quotient_a[i+1][XLEN-i-2:0]    = quotient_a[i][XLEN-i-2:0];
                end

            end
        end
    endgenerate

    // Pipeline Outputs
    assign quotient_o  = quotient_a[XLEN];
    assign remainder_o = dividend_a[XLEN];
    assign done_o      = valid[NUM_STAGES];

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
