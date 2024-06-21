///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: pipeline_controller                                                              //
// Description: This module handles pipeline stage timing and invalidation based on various      //
//              hazards detected within the pipeline.                                            //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module pipeline_controller (
    //================= Clocks, Resets ==================//
    input               clk_i,
    input               rst_ni,

    //================= Hazard Inputs ===================//
    input               imem_stall_i,
    input               dmem_stall_i,
    input               load_use_haz_i,
    input               csr_load_use_haz_i,
    input               alu_stall_i,
    input               fencei_i,
    input               mem_exc_i,
    input               trap_i,

    //============= Pipeline State Inputs ===============//
    input               EXE_branch_i,
    input               EXE_write_i,
    input               MEM_write_i,
    input               valid_inst_in_pipe_i,

    //============= Interrupt Controls ==================//
    input               wait_for_int_i,
    input               interrupt_i,
    output wire         interrupt_o,

    //============= Stage Control Outputs ===============//
    output wire         FCH_squash_o,
    output wire         FCH_bubble_o,
    output wire         FCH_stall_o,

    output wire         DCD_squash_o,
    output wire         DCD_bubble_o,
    output wire         DCD_stall_o,

    output wire         EXE_squash_o,
    output wire         EXE_bubble_o,
    output wire         EXE_stall_o,

    output wire         MEM_squash_o,
    output wire         MEM_bubble_o,
    output wire         MEM_stall_o,

    output wire         WB_squash_o,
    output wire         WB_bubble_o,
    output wire         WB_stall_o,

    //============= Core External Outputs ===============//
    output wire         fencei_flush_ao
);

    wire branch_taken   = EXE_branch_i || trap_i;
    wire fencei_flush_a = (EXE_write_i || MEM_write_i) && fencei_i;
    
    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        Interrupts                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg flush_in_progress, waiting_for_int;

    always @(posedge clk_i) begin
        if (~rst_ni || ~valid_inst_in_pipe_i)
            flush_in_progress <= 'b0;
        else if (interrupt_i)
            flush_in_progress <= 'b1;
    end

    always @(posedge clk_i) begin
        if (~rst_ni || interrupt_i)
            waiting_for_int <= 'b0;
        else if (wait_for_int_i)
            waiting_for_int <= 'b1;
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          Outputs                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    
    assign FCH_squash_o = branch_taken || mem_exc_i || flush_in_progress || ~rst_ni;
    assign FCH_bubble_o = 'b0;
    assign FCH_stall_o  = imem_stall_i   || dmem_stall_i || load_use_haz_i || waiting_for_int ||
                          fencei_flush_a || alu_stall_i  || csr_load_use_haz_i;

    assign DCD_squash_o = branch_taken || mem_exc_i || ~rst_ni;
    assign DCD_bubble_o = imem_stall_i || fencei_flush_a || csr_load_use_haz_i;
    assign DCD_stall_o  = dmem_stall_i || load_use_haz_i || alu_stall_i || waiting_for_int;

    assign EXE_squash_o = mem_exc_i || ~rst_ni;
    assign EXE_bubble_o = load_use_haz_i || waiting_for_int;
    assign EXE_stall_o  = dmem_stall_i || alu_stall_i;

    assign MEM_squash_o = ~rst_ni;
    assign MEM_bubble_o = alu_stall_i;
    assign MEM_stall_o  = dmem_stall_i;

    assign WB_squash_o  = ~rst_ni;
    assign WB_bubble_o  = 'b0;
    assign WB_stall_o   = dmem_stall_i;


    assign fencei_flush_ao = fencei_flush_a;
    assign interrupt_o = flush_in_progress;


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
