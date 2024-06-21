///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: bypass_unit                                                                      //
// Description: A simple 2-stage bypass/forwarding unit for a source register. Load use          //
//              hazards are detected by this unit, but handling them is left to the user.        //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module bypass_unit (
    //======= Clocks, Resets, and Stage Controls ========//
    input                   clk_i,
    input                   rst_ni,
    
    input                   bubble_i,
    input                   stall_i,
    
    //============ Forwarded register inputs ============//
    input                   EXE_mem_read_i,
    input                   EXE_rd_wr_en_i,  MEM_rd_wr_en_i,
    input                   EXE_valid_i,     MEM_valid_i,
    input      [4:0]        EXE_rd_idx_i,    MEM_rd_idx_i,
    input   [`XLEN-1:0]     EXE_rd_data_i,   MEM_rd_data_i,

    //============= Source Register Inputs ==============//
    input      [4:0]        rs_idx_i,
    input   [`XLEN-1:0]     rs_data_i,
    input                   rs_used_i,

    //====== Updated Register and Hazard Indicator ======//
    output wire [`XLEN-1:0] rs_data_ao,
    output wire             load_use_hazard_ao
);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                Retired Instruction Tracker                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // If an instruction waits in execute while writes retire to the register file, bypass data 
    // will become unavailable. To solve this, retired writes are recorded during wait states
    reg [`XLEN-1:0] retired_reg_wr_value;
    reg           retired_reg_wr_valid;

    wire EXE_waiting = bubble_i || stall_i;

    always @(posedge clk_i) begin
        if (~rst_ni) begin
            retired_reg_wr_value        <= 'b0;
            retired_reg_wr_valid        <= 'b0;            
        end else begin
            if ((MEM_rd_idx_i == rs_idx_i) && MEM_rd_wr_en_i && EXE_waiting) begin
                retired_reg_wr_value    <= MEM_rd_data_i;
                retired_reg_wr_valid    <= 'b1; 
            end else if (~EXE_waiting)
                retired_reg_wr_valid    <= 'b0; 
        end
    end

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       Bypass Logic                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Signals to identify if a RAW conflict is possible (registers_i match)
    reg mem_conflict, exe_conflict;
    reg mem_raw, exe_raw;
    reg [`XLEN-1:0] data_updated;

    always @ (*) begin
        mem_conflict = (rs_idx_i == MEM_rd_idx_i);
        exe_conflict = (rs_idx_i == EXE_rd_idx_i);

        mem_raw = (mem_conflict && MEM_rd_wr_en_i && MEM_valid_i && rs_used_i);
        exe_raw = (exe_conflict && EXE_rd_wr_en_i && EXE_valid_i && rs_used_i);

        // Update data with higher precedence to newer writes
        data_updated = rs_data_i;
        if (retired_reg_wr_valid) data_updated = retired_reg_wr_value;
        if (mem_raw)              data_updated = MEM_rd_data_i;
        if (exe_raw)              data_updated = EXE_rd_data_i;
    end


    assign load_use_hazard_ao = exe_raw && EXE_mem_read_i;
    assign rs_data_ao         = data_updated;

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
