///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: memory_stage                                                                     //
// Description: Memory Stage. This stage slices outgoing data based on data with and sub-line    //
//              addressing, and drives the data memory read/write transactions.                  //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module memory_stage (
    //======= Clocks, Resets, and Stage Controls ========//
    input               clk_i,
    input               rst_ni,
    
    input               squash_i,
    input               stall_i,

    //============== Execute Stage Inputs ===============//
    input               valid_i,
    input [63:0]        alu_result_i,
    input [63:0]        rs2_data_i,
    // Destination Register (rd)
    input  [63:0]       rd_data_i,
    input  [4:0]        rd_idx_i,
    input               rd_wr_en_i,
    input  [2:0]        rd_wr_src_1h_i,
    // Load/Store
    input  [3:0]        mem_width_1h_i,
    input               mem_rd_i,
    input               mem_wr_i,
    input               mem_sign_i,

    //============== Data Memory Interface ==============//
    output wire         dmem_req_o,
    input               dmem_gnt_i,
    output wire  [63:0] dmem_addr_ao,
    output wire         dmem_we_ao,
    output wire  [7:0]  dmem_be_ao,
    output reg   [63:0] dmem_wdata_ao,
    input               dmem_rvalid_i,

    output wire         dmem_stall_ao,
    output wire         dmem_illegal_ao,

    //================ Pipeline Outputs =================//
    output reg          valid_o,
    // Destination Register (rd)
    output reg  [63:0]  rd_data_o,
    output reg  [4:0]   rd_idx_o,
    output reg          rd_wr_en_o,
    output reg  [2:0]   rd_wr_src_1h_o,
    // Load/Store
    output reg  [3:0]   mem_width_1h_o,
    output reg          mem_sign_o,
    output reg  [2:0]   byte_addr_o
);

    wire valid = valid_i & ~squash_i;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    Byte Addressing Logic                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [63:0] dmem_full_addr,  dmem_word_addr;
    reg  [63:0] dmem_wdata_a;
    reg         illegal_addr;
    reg  [7:0]  byte_strobe;
    wire [2:0]  byte_addr = dmem_full_addr[2:0];
    

    always @ (*) begin : dmem_strobe_gen
        case (mem_width_1h_i)
            `MEM_WIDTH_1H_BYTE: begin
                illegal_addr      = 1'b0;
                dmem_wdata_a      = { 8{rs2_data_i[7:0]} };
                byte_strobe       = (8'b0000_0001 << byte_addr);
            end
            `MEM_WIDTH_1H_HALF: begin 
                illegal_addr      = (byte_addr == 3'b111);
                dmem_wdata_a      = { 4{rs2_data_i[15:0]} };
                byte_strobe       = (illegal_addr) ? 8'b0 : (8'b0000_0011 << byte_addr);
            end
            `MEM_WIDTH_1H_WORD: begin 
                illegal_addr      = (byte_addr > 3'b100);
                dmem_wdata_a      = { 2{rs2_data_i[31:0]} };
                byte_strobe       = (illegal_addr) ? 8'b0 : (8'b0000_1111 << byte_addr);
            end
            `MEM_WIDTH_1H_DOUBLE: begin 
                illegal_addr      = (byte_addr != 3'b0);
                dmem_wdata_a      = rs2_data_i;
                byte_strobe       = (illegal_addr) ? 8'b0 : 8'b1111_1111;
            end
            default: begin
                illegal_addr      = 1'b1;
                dmem_wdata_a      = rs2_data_i;
                byte_strobe       = 8'b0;
            end
        endcase
    end
    
    assign dmem_full_addr = alu_result_i;
    assign dmem_word_addr  = {dmem_full_addr[63:2], 2'b0};
    assign dmem_illegal_ao = ( illegal_addr && (mem_read || mem_write) );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 Host Memory Request Driver                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire mem_read  = mem_rd_i & ~squash_i & valid_i;
    wire mem_write = mem_wr_i & ~squash_i & valid_i;

    obi_host_driver dmem_obi_host_driver 
    (
        .clk_i,
        .rst_ni,

        .gnt_i    (dmem_gnt_i),
        .rvalid_i (dmem_rvalid_i),

        .stall_i,

        .be_i     ((mem_write) ? byte_strobe : 8'b0),
        .addr_i   (dmem_word_addr),
        .wdata_i  (dmem_wdata_a),
        .rd_i     (mem_read),
        .wr_i     (mem_write),

        .stall_ao (dmem_stall_ao),

        .req_o    (dmem_req_o),
        .we_ao    (dmem_we_ao),
        .be_ao    (dmem_be_ao),
        .addr_ao  (dmem_addr_ao),
        .wdata_ao (dmem_wdata_ao)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //        ____  _            _ _              ____            _     _                        //
    //       |  _ \(_)_ __   ___| (_)_ __   ___  |  _ \ ___  __ _(_)___| |_ ___ _ __ ___         //
    //       | |_) | | '_ \ / _ \ | | '_ \ / _ \ | |_) / _ \/ _` | / __| __/ _ \ '__/ __|        //
    //       |  __/| | |_) |  __/ | | | | |  __/ |  _ <  __/ (_| | \__ \ ||  __/ |  \__ \        //
    //       |_|   |_| .__/ \___|_|_|_| |_|\___| |_| \_\___|\__, |_|___/\__\___|_|  |___/        //
    //               |_|                                    |___/                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk_i) begin : execute_pipeline_registers
    // On reset, all signals set to 0; on stall, all outputs do not change.
        valid_o         <= ~rst_ni ? 'b0 : (stall_i ? valid_o         : valid );
        // Destination Register (rd) 
        rd_data_o       <= ~rst_ni ? 'b0 : (stall_i ? rd_data_o       : rd_data_i );
        rd_idx_o        <= ~rst_ni ? 'b0 : (stall_i ? rd_idx_o        : rd_idx_i );
        rd_wr_en_o      <= ~rst_ni ? 'b0 : (stall_i ? rd_wr_en_o      : rd_wr_en_i );
        rd_wr_src_1h_o  <= ~rst_ni ? 'b0 : (stall_i ? rd_wr_src_1h_o  : rd_wr_src_1h_i );
        // Load/Store 
        mem_width_1h_o  <= ~rst_ni ? 'b0 : (stall_i ? mem_width_1h_o  : mem_width_1h_i );
        mem_sign_o      <= ~rst_ni ? 'b0 : (stall_i ? mem_sign_o      : mem_sign_i );
        byte_addr_o     <= ~rst_ni ? 'b0 : (stall_i ? byte_addr_o     : dmem_full_addr[2:0] );
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
