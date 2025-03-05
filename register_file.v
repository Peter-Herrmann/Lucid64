///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: register_file                                                                    //
// Description: A 31 x XLEN register file with read-only-zero 0th register. Reads are            //
//              asynchronous and writes are synchronous. Write data is bypassed to the read port //
//              in the case of RAW conflicts at the register file interfaces.
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: CC-BY-NC-ND-4.0                                                      //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////


module register_file #( parameter XLEN = 64 ) (
    input                  clk_i,

    input            [4:0] rs1_idx_i,   // Register source 1 index
    input            [4:0] rs2_idx_i,   // Register source 2 index
    input            [4:0] rd_idx_i,    // Destination Register index

    input       [XLEN-1:0] wr_data_i,   // Write data input
    input                  wr_en_i,     // Write strobe

    output reg [XLEN-1:0] rs1_data_ao, // rs1 data output (async)
    output reg [XLEN-1:0] rs2_data_ao  // rs2 data output (async)
);

    reg [XLEN-1:0] RF [31:1]; 
    
    reg            rs1_bypass, rs2_bypass;
    reg [XLEN-1:0] rs1_rdata,  rs2_rdata;

    // Read control. 
    always @(*) begin
        rs1_bypass = (rs1_idx_i == rd_idx_i) && wr_en_i;
        rs2_bypass = (rs2_idx_i == rd_idx_i) && wr_en_i;

        // Bypass write data to decode stage. This is similar to having writes on negedge.
        rs1_rdata  = rs1_bypass ? wr_data_i : RF[rs1_idx_i];
        rs2_rdata  = rs2_bypass ? wr_data_i : RF[rs2_idx_i];

        // Returns 0 if reading from x0.
        rs1_data_ao = (rs1_idx_i != 'b0) ? rs1_rdata : 'b0;
        rs2_data_ao = (rs2_idx_i != 'b0) ? rs2_rdata : 'b0;
    end

    // Write control. Will not write to x0.
    always @ (posedge clk_i) begin
        if(wr_en_i && (rd_idx_i != 'b0)) 
            RF[rd_idx_i] <= wr_data_i;
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
