///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: obi_host_driver                                                                  //
// Description: This module handles driving memory reads and writes through an OBI interface.    //
//              It manages request and response stalls internally, including re-winding outputs  //
//              during stalls.                                                                   //
//                                                                                               //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////

module obi_host_driver #(
    parameter DATA_W  = 64, 
    parameter ADDR_W  = 39,
    parameter BE_BITS = (DATA_W / 8 )
    ) (
    //======= Clock, Reset, and Memory Flow Control ======//
    input                   clk_i,
    input                   rst_ni,

    input                   gnt_i,
    input                   rvalid_i,

    input                   stall_i,

    //============== Host Memory Controls ===============//
    input [BE_BITS-1:0]     be_i,
    input [ADDR_W-1:0]      addr_i,
    input [DATA_W-1:0]      wdata_i,
    input                   rd_i,
    input                   wr_i,

    //===================== Outputs =====================//
    output wire                 stall_ao,
    // Memory request outputs
    output wire                 req_o,
    output wire                 we_ao,
    output wire [BE_BITS-1:0]   be_ao,
    output wire [ADDR_W-1:0]    addr_ao,
    output wire [DATA_W-1:0]    wdata_ao
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       Output Rewinder                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg [ADDR_W-1:0]    addr_saved;
    reg [DATA_W-1:0]    wdata_saved;
    reg [BE_BITS-1:0]   be_saved;
    reg                 we_saved, read_saved, req;
    wire                read, stall;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            read_saved  <= 'b0;
            we_saved    <= 'b0;
            be_saved    <= 'b0;
            addr_saved  <= 'b0;
            wdata_saved <= 'b0;
        end else if (~stall && req) begin
            read_saved  <= rd_i;
            we_saved    <= wr_i;
            be_saved    <= be_i;
            addr_saved  <= addr_i;
            wdata_saved <= wdata_i;
        end
    end

    assign read = (stall) ? read_saved : rd_i;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 Transaction State Machine                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg  read_outstanding, read_accepted, request_stall_r;

    wire response_stall_a = read_outstanding ? ~rvalid_i : 'b0;
    wire request_stall_a  = req && (~gnt_i);

    always @(posedge clk_i) begin
        if (~rst_ni) begin
            read_outstanding <= 'b0;
            request_stall_r  <= 'b0;
        end else begin
            read_outstanding <= read_accepted;
            request_stall_r  <= request_stall_a;
        end
    end

    always @ (*) begin
        if (read_outstanding) begin
            read_accepted    = !(rvalid_i && !(rd_i && gnt_i));
            req              =   rvalid_i &&  (rd_i || wr_i);
        end else begin
            read_accepted    = (read && gnt_i);
            req              = (rd_i || wr_i) || request_stall_r;
        end 
    end
    
    assign stall = request_stall_r || response_stall_a || stall_i;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          Outputs                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    assign we_ao    = (stall) ? we_saved    : wr_i;
    assign be_ao    = (stall) ? be_saved    : be_i;
    assign addr_ao  = (stall) ? addr_saved  : addr_i;
    assign wdata_ao = (stall) ? wdata_saved : wdata_i;
    assign req_o    = req;
    assign stall_ao = (request_stall_r || response_stall_a);


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
