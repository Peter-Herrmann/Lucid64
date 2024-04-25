///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: obi_host_driver                                                                  //
// Description: This module drives the req and stall signals for an OBI (Open Bus                //
//              Interface) master. The rd and wr inputs indicate that a read or                  //
//              write transaction is desired, and the gnt and rvalid signal come                 //
//              from the OBI slave device directly. The stall signal is routed                   //
//              back to the master for hazard management and the req signal is                   //
//              output onto the OBI bus.                                                         //
//                                                                                               //
//              The unit does not support multiple outstanding reads.                            //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module obi_host_driver(
        input           clk_i,
        input           rst_ni,

        input           rd_i,
        input           wr_i,

        input           gnt_i,
        input           rvalid_i,

        output reg      stall_o,
        output reg      req_o
);

  reg NS, PS;
  reg stall_a, stall_next, stall_next_a;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        Stall Buffer                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // TODO - If at all possible, this negedge should be removed
    always @(negedge clk_i) begin
        if (~rst_ni) begin
            stall_o    <= 'b0;
            stall_next <= 'b0;
        end else begin
            stall_o    <= stall_a || stall_next;
            stall_next <= stall_next_a;
        end
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       Next State Decoder                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @ (*) begin
        case (PS)
            `MEM_PHASE_ADDR: 
                NS = (rd_i && gnt_i)                ? `MEM_PHASE_RESP : `MEM_PHASE_ADDR;
            `MEM_PHASE_RESP: 
                NS = (rvalid_i && ~(rd_i && gnt_i)) ? `MEM_PHASE_ADDR : `MEM_PHASE_RESP;
            default: 
                NS = `MEM_PHASE_ADDR;
        endcase
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       Next State Register                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk_i) begin
        if (~rst_ni) 
            PS <= `MEM_PHASE_ADDR;
        else 
            PS <= NS;
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         Output Decoder                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @ (*) begin
        case (PS)
            `MEM_PHASE_ADDR: begin
                req_o        = ~rst_ni ? 'b0 : (rd_i || wr_i);
                stall_a      = ( (rd_i || wr_i) && ~gnt_i);
                stall_next_a = ( (rd_i || wr_i) && ~gnt_i);
            end

            `MEM_PHASE_RESP: begin
                req_o        = ~rst_ni ? 'b0 : (rd_i || wr_i) && rvalid_i;
                stall_a      = ~rvalid_i;
                stall_next_a = ( ( (rd_i || wr_i) && rvalid_i ) && ~gnt_i );
            end

            default: begin
                req_o        = 'b0;
                stall_a      = 'b0;
                stall_next_a = 'b0;
            end
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
