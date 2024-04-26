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
    input               imem_gnt_i,
    input               imem_rvalid_i,
    output wire         imem_req_o,
    output wire [63:0]  imem_addr_o,
    output wire         imem_stall_o,
    
    //================ Pipeline Outputs =================//
    output reg          valid_o,
    output reg  [63:0]  pc_o,
    output reg  [63:0]  next_pc_o
);

    wire valid = ~squash_i;

    wire imem_stall;
    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  Branch Control Synchronizer                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg [63:0] target_saved;
    reg        branch_ctrl_saved, target_sel_saved;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            target_saved        <= 'b0;
            target_sel_saved    <= 'b0;
            branch_ctrl_saved   <= 'b0;
        end else if (~stall_i) begin
            branch_ctrl_saved   <= 'b0;
        end else if (imem_stall && ~branch_ctrl_saved) begin
            target_saved        <= target_addr_i;
            target_sel_saved    <= target_sel_i;
            branch_ctrl_saved   <= 'b1;
        end
    end
    

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                Program Counter and Branch MUX                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [63:0] next_pc, pc_out, target_addr;
    reg  [63:0] last_pc, pc_raw;
    wire        target_sel;

    assign target_sel  = branch_ctrl_saved              ? target_sel_saved : target_sel_i;
    assign target_addr = branch_ctrl_saved              ? target_saved     : target_addr_i;
    assign next_pc     = (target_sel == `PC_SRC_BRANCH) ? target_addr      : (pc_out + 4);

    always @(posedge clk_i) begin
        if (~rst_ni) begin
            last_pc <= `RESET_ADDR;
            pc_raw  <= `RESET_ADDR;
        end else if (~stall_i) begin
            last_pc <= pc_raw; 
            pc_raw  <= next_pc;
        end
    end

    assign pc_out = stall_i ? last_pc : pc_raw;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 Instruction Memory Interface                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    obi_host_driver imem_obi_host_driver 
    (
        .clk_i,
        .rst_ni,

        .gnt_i    (imem_gnt_i),
        .rvalid_i (imem_rvalid_i),

        .be_i     ('b0),
        .addr_i   (pc_raw),
        .wdata_i  ('b0),
        .rd_i     ('b1),
        .wr_i     ('b0),

        .stall_ao (imem_stall),

        .req_o    (imem_req_o),
        .we_ao    (),
        .be_ao    (),
        .addr_ao  (imem_addr_o),
        .wdata_ao ()
    );

    assign imem_addr_o  = pc_out;
    assign imem_stall_o = imem_stall;



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
