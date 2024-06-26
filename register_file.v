///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: register_file                                                                    //
// Description: A 31 x XLEN register file with read-only-zero 0th register. Reads are            //
//              asynchronous and writes happen on negedge.                                       //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: CC-BY-NC-ND-4.0                                                      //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////


module register_file #( parameter XLEN = 64 ) (
    input                  clk_i,       // Negedge sensitive

    input            [4:0] rs1_idx_i,   // Register source 1 index
    input            [4:0] rs2_idx_i,   // Register source 2 index
    input            [4:0] rd_idx_i,    // Destination Register index

    input       [XLEN-1:0] wr_data_i,   // Write data input
    input                  wr_en_i,     // Write strobe

    output wire [XLEN-1:0] rs1_data_ao, // rs1 data output (async)
    output wire [XLEN-1:0] rs2_data_ao  // rs2 data output (async)
);
    
    reg [XLEN-1:0] RF [31:1]; 

    // Read control. Returns 0 if reading from x0.
    assign rs1_data_ao = (rs1_idx_i != 'b0) ? RF[rs1_idx_i] : 'b0;
    assign rs2_data_ao = (rs2_idx_i != 'b0) ? RF[rs2_idx_i] : 'b0;


    // Write control (On NEGEDGE). Will not write to x0.
    always @ (negedge clk_i) begin
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
