///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: fetch_stage                                                                      //
// Description: Fetch Stage. Manages the program counter, drives the instruction memory port,    //
//              keeps the program counter syncronized during stalls.                             // 
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module fetch_stage (
    //======= Clocks, Resets, and Stage Controls ========//
    input               clk_i,
    input               rst_ni,
    
    input               squash_i,
    input               stall_i,

    //============== Branch Control Inputs ==============//
    input               target_sel_i,
    input       [63:0]  target_addr_i,

    //========== Instruction Memory Interface ===========//
    output wire         imem_req_o,
    input               imem_gnt_i,
    output wire  [63:0] imem_addr_o,
    output wire         imem_we_o,
    output wire  [3:0]  imem_be_o,
    output wire  [31:0] imem_wdata_o,
    input               imem_rvalid_i,

    output wire         imem_stall_ao,
    
    //================ Pipeline Outputs =================//
    output reg          valid_o,
    output reg  [63:0]  pc_o,
    output reg  [63:0]  next_pc_o
);

    wire valid = ~squash_i;

    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  Branch Target Re-Winder                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg stall_delayed;
    wire [63:0] next_pc, next_pc_current;
    reg  [63:0] next_pc_saved;

    assign next_pc_current = (target_sel_i == `PC_SRC_BRANCH) ? target_addr_i : (pc_out + 4);

    always @(posedge clk_i) begin
        if (~rst_ni)                stall_delayed <= 'b0;
        else                        stall_delayed <= stall_i;
    end

    always @(posedge clk_i) begin
        if (~rst_ni)                next_pc_saved <= 'b0;
        else if (~stall_delayed)    next_pc_saved <= next_pc_current;
    end

    assign next_pc = stall_delayed ? next_pc_saved : next_pc_current;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Program Counter                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg  [63:0] pc_out;

    always @(posedge clk_i) begin
        if      (~rst_ni)   pc_out <= `RESET_ADDR;
        else if (~stall_i)  pc_out <= next_pc;
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                               Instruction Memory Interface                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    obi_host_driver imem_obi_host_driver 
    (
        .clk_i,
        .rst_ni,

        .gnt_i    (imem_gnt_i),
        .rvalid_i (imem_rvalid_i),

        .be_i     ('b0),
        .addr_i   (pc_out),
        .wdata_i  ('b0),
        .rd_i     ('b1),
        .wr_i     ('b0),

        .stall_ao (imem_stall_ao),

        .req_o    (imem_req_o),
        .we_ao    (imem_we_o),
        .be_ao    (imem_be_o),
        .addr_ao  (imem_addr_o),
        .wdata_ao (imem_wdata_o)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //        ____  _            _ _              ____            _     _                        //
    //       |  _ \(_)_ __   ___| (_)_ __   ___  |  _ \ ___  __ _(_)___| |_ ___ _ __ ___         //
    //       | |_) | | '_ \ / _ \ | | '_ \ / _ \ | |_) / _ \/ _` | / __| __/ _ \ '__/ __|        //
    //       |  __/| | |_) |  __/ | | | | |  __/ |  _ <  __/ (_| | \__ \ ||  __/ |  \__ \        //
    //       |_|   |_| .__/ \___|_|_|_| |_|\___| |_| \_\___|\__, |_|___/\__\___|_|  |___/        //
    //               |_|                                    |___/                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk_i) begin
    // On reset, all signals set to 0; on stall, all outputs do not change.
        valid_o   <= ~rst_ni ? 'b0 : (stall_i ? valid_o   : valid);
        // Current Program Counter and Return Address
        pc_o      <= ~rst_ni ? 'b0 : (stall_i ? pc_o      : pc_out);
        next_pc_o <= ~rst_ni ? 'b0 : (stall_i ? next_pc_o : pc_out + 4);
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
