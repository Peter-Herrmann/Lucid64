///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: writeback_stage                                                                  //
// Description: Writeback Stage. Slices up the 64 bit read from memory as needed and controls    //
//              all writes to the register file.                                                 //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module writeback_stage (
    //======= Clocks, Resets, and Stage Controls ========//
    input               clk_i,
    input               rst_ni,
    
    input               squash_i,
    input               stall_i,

    //============= Memory Pipeline Inputs ==============//
    input               valid_i,
    // Destination Register (rd)
    input       [63:0]  rd_data_i,
    input       [4:0]   rd_idx_i,
    input               rd_wr_en_i,
    input       [2:0]   rd_wr_src_1h_i,
    // Data Memory Load Inputs
    input        [63:0] dmem_rdata_i,
    input        [3:0]  mem_width_1h_i,
    input               mem_sign_i,
    input        [2:0]  byte_addr_i,

    //============= Register File Controls ==============//
    output wire [63:0]  rd_data_o,
    output wire [4:0]   rd_idx_o,
    output wire         rd_wr_en_o,

    output wire valid_ao
);
    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Validity Tracker                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg  squashed_during_stall;

    always @(posedge clk_i) begin
        if (~rst_ni) 
            squashed_during_stall <= 'b0;
        if (stall_i && squash_i) 
            squashed_during_stall <= 'b1;
        else if (~stall_i) 
            squashed_during_stall <= 'b0;
    end

    wire valid = valid_i && ~squash_i && ~squashed_during_stall;

    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    Byte Addressing Logic                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [7:0]  bytes [0:7];
    wire [15:0] halfs [0:3];
    wire [31:0] words [0:1];
    reg [63:0] load_data_sliced;
    reg        msb;


    assign { bytes[7], bytes[6], bytes[5], bytes[4], 
             bytes[3], bytes[2], bytes[1], bytes[0] } = dmem_rdata_i[63:0];
    assign { halfs[3], halfs[2], halfs[1], halfs[0] } = dmem_rdata_i[63:0];
    assign { words[1], words[0] }                     = dmem_rdata_i[63:0];


    always @ (*) begin
        case (mem_width_1h_i)
            `MEM_WIDTH_1H_BYTE:   begin
                msb              = (mem_sign_i == `MEM_SIGNED) ? bytes[byte_addr_i][7] : 1'b0;
                load_data_sliced = { {56{msb}}, bytes[byte_addr_i]} ;
            end
            `MEM_WIDTH_1H_HALF:   begin
                msb              = (mem_sign_i == `MEM_SIGNED) ? halfs[byte_addr_i[2:1]][15] : 1'b0;
                load_data_sliced = { {48{msb}}, halfs[byte_addr_i[2:1]] };
            end
            `MEM_WIDTH_1H_WORD:   begin
                msb              = (mem_sign_i == `MEM_SIGNED) ? words[byte_addr_i[2]][31] : 1'b0;
                load_data_sliced = { {32{msb}}, words[byte_addr_i[2]] };
            end
            `MEM_WIDTH_1H_DOUBLE: begin
                msb              = dmem_rdata_i[63];
                load_data_sliced = dmem_rdata_i;
            end
            default: begin
                msb              = 1'b0;
                load_data_sliced = 'b0;
            end
        endcase
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  Register File Controls                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Update load instuctions with correct source (alu/pc sources handled in execute) 
    assign rd_data_o  = (rd_wr_src_1h_i[1]) ? load_data_sliced : rd_data_i;
    assign rd_idx_o   = rd_idx_i;
    assign rd_wr_en_o = rd_wr_en_i && valid && ~stall_i;

    assign valid_ao = valid;

`ifdef VERILATOR
    wire _unused = &{rd_wr_src_1h_i};
`endif

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
