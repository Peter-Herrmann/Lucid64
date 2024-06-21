///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: fetch_stage                                                                      //
// Description: This stage manages the program counter, drives the instruction memory port, and  //
//              keeps the program counter synchronized during any pipeline hazards.              // 
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: CC-BY-NC-ND-4.0                                                      //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module fetch_stage #(parameter VADDR = 39, parameter RESET_ADDR = 0) (
    //======= Clocks, Resets, and Stage Controls ========//
    input                   clk_i,
    input                   rst_ni,
    
    input                   squash_i,
    input                   bubble_i,
    input                   stall_i,
    input                   fencei_i,

    input                   compressed_instr_i,

    //============== Branch Control Inputs ==============//
    input                   branch_i,
    input       [VADDR-1:0] target_addr_i,
    // Interrupt branch
    input                   csr_branch_i,
    input       [VADDR-1:0] csr_branch_addr_i,
    // xRET branch
    input                   trap_ret_i,
    input       [VADDR-1:0] trap_ret_addr_i,

    //========== Instruction Memory Interface ===========//
    output wire             imem_req_o,
    output wire [VADDR-1:0] imem_addr_ao,
    input                   imem_gnt_i,
    input                   imem_rvalid_i,

    output wire             imem_stall_ao,
    
    //================ Pipeline Outputs =================//
    output reg              valid_o,
    output reg [VADDR-1:0]  pc_o,
    output reg [VADDR-1:0]  next_pc_o
);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Validity Tracker                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire valid;

    validity_tracker FCH_validity_tracker (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),

        .valid_i        (1'b1),
        
        .squash_i       (squash_i),
        .bubble_i       (bubble_i),
        .stall_i        (stall_i),

        .valid_ao       (valid)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                            Program Counter Target Synchronizer                            //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg stall_delayed, branch_taken_r, branch_taken_saved;
    reg [VADDR-1:0] pc, next_pc, next_pc_current, next_pc_saved, pc_updated;

    wire branch_taken = (trap_ret_i || branch_i || csr_branch_i);

    // Delayed stall for saving (1st stall cycle) and restoring (1st cycle after stall) PC target
    always @(posedge clk_i) begin
        stall_delayed <= (rst_ni) ? stall_i : 1'b0;
    end

    always @(posedge clk_i) begin
        if (~rst_ni) begin
            next_pc_saved      <= 'b0;
            branch_taken_saved <= 'b0;
        end else if (~stall_delayed) begin
            next_pc_saved      <= next_pc_current;
            branch_taken_saved <= branch_taken;
        end else if (branch_i) begin
            next_pc_saved      <= target_addr_i;
        end
    end

    always @(*) begin
        if      (csr_branch_i) next_pc_current = csr_branch_addr_i;
        else if (branch_i)     next_pc_current = target_addr_i;    
        else if (trap_ret_i)   next_pc_current = trap_ret_addr_i;
        else                   next_pc_current = (pc + 4);
        // During stalls, the previous instruction is not yet decoded, so it is not known if the 
        // instruction is compressed. When saving PC targets, speculate that the increment is 4,
        // then update when retrieving the saved value.
    end

    always @(*) begin
        pc_updated = stall_delayed ? next_pc_saved : next_pc_current;

        if (branch_i) begin
            // Update branch target when the branch target is a load-use dependency
            next_pc = target_addr_i;
        end else if (~branch_taken || (stall_delayed && ~branch_taken_saved)) begin
            // Update PC with corrected increment for compressed instructions if necessary
            next_pc = compressed_instr_i ? (pc_updated - 2) : pc_updated;
        end else
            next_pc = pc_updated;
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Program Counter                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [VADDR-1:0] pc_out;

    always @(posedge clk_i) begin
        if      (~rst_ni)   pc <= RESET_ADDR;
        else if (~stall_i)  pc <= next_pc & (~('b1));
    end

    always @(posedge clk_i) begin
        if      (~rst_ni)   branch_taken_r <= 'b0;
        else if (~stall_i)  branch_taken_r <= branch_taken;
    end

    assign pc_out = (compressed_instr_i && ~branch_taken_r) ? (pc - 2) : pc;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                               Instruction Memory Interface                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [31:0] wdata;
    wire [3:0]  be;
    wire        we;
    wire        read = valid && ~fencei_i;

    obi_host_driver #(.DATA_W(32), .ADDR_W(VADDR)) imem_obi_host_driver 
    (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),

        .gnt_i    (imem_gnt_i),
        .rvalid_i (imem_rvalid_i),

        .stall_i  (stall_i),

        .be_i     (4'b0),
        .addr_i   (pc_out),
        .wdata_i  (32'b0),
        .rd_i     (read),
        .wr_i     (1'b0),

        .stall_ao (imem_stall_ao),

        .req_o    (imem_req_o),
        .we_ao    (we),
        .be_ao    (be),
        .addr_ao  (imem_addr_ao),
        .wdata_ao (wdata)
    );

`ifdef VERILATOR
    wire _unused = &{we, be, wdata};
`endif


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //        ____               _                ____                  _                        //
    //       |  _ \(_)_ __   ___| (_)_ __   ___  |  _ \ ___  __ _(_)___| |_ ___ _ __ ___         //
    //       | |_) | | '_ \ / _ \ | | '_ \ / _ \ | |_) / _ \/ _` | / __| __/ _ \ '__/ __|        //
    //       |  __/| | |_) |  __/ | | | | |  __/ |  _ <  __/ (_| | \__ \ ||  __/ |  \__ \        //
    //       |_|   |_| .__/ \___|_|_|_| |_|\___| |_| \_\___|\__, |_|___/\__\___|_|  |___/        //
    //               |_|                                    |___/                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk_i) begin
    // On reset, all signals set to 0; on stall, all outputs do not change.
        valid_o   <= (stall_i ? valid_o   : valid);
        pc_o      <= (stall_i ? pc_o      : pc_out);
        next_pc_o <= (stall_i ? next_pc_o : pc_out + 4);
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
