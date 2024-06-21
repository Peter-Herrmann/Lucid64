///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: memory_stage                                                                     //
// Description: Memory Stage. This stage slices outgoing data based on data with and sub-line    //
//              addressing, and drives the data memory read/write transactions.                  //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: CC-BY-NC-ND-4.0                                                      //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module memory_stage #(parameter VADDR = 39) (
    //======= Clocks, Resets, and Stage Controls ========//
    input                   clk_i,
    input                   rst_ni,
    
    input                   squash_i,
    input                   bubble_i,
    input                   stall_i,

    //============== Execute Stage Inputs ===============//
    input                   valid_i,
    input [VADDR-1:0]       dmem_full_addr_i,
    input [`XLEN-1:0]       rs2_data_i,
    // Destination Register (rd)
    input  [`XLEN-1:0]      rd_data_i,
    input  [4:0]            rd_idx_i,
    input                   rd_wr_en_i,
    input                   rd_wr_src_load_i,
    // Load/Store
    input  [3:0]            mem_width_1h_i,
    input                   mem_rd_i,
    input                   mem_wr_i,
    input                   mem_sign_i,

    //============== Data Memory Interface ==============//
    output wire             dmem_req_o,
    input                   dmem_gnt_i,
    output wire [VADDR-1:0] dmem_addr_ao,
    output wire             dmem_we_ao,
    output wire  [7:0]      dmem_be_ao,
    output wire [`XLEN-1:0] dmem_wdata_ao,
    input                   dmem_rvalid_i,

    output wire             dmem_stall_ao,
    output wire             unalign_store_ex_ao,
    output wire             unalign_load_ex_ao,

    //================ Pipeline Outputs =================//
    output reg              valid_o,
    // Destination Register (rd)
    output reg  [`XLEN-1:0] rd_data_o,
    output reg  [4:0]       rd_idx_o,
    output reg              rd_wr_en_o,
    output reg              rd_wr_src_load_o,
    // Load/Store
    output reg  [3:0]       mem_width_1h_o,
    output reg              mem_sign_o,
    output reg  [2:0]       byte_addr_o
);
    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Validity Tracker                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire valid;

    validity_tracker MEM_validity_tracker (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),

        .valid_i        (valid_i),
        
        .squash_i       (squash_i),
        .bubble_i       (bubble_i),
        .stall_i        (stall_i),

        .valid_ao       (valid)
    );

    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    Byte Addressing Logic                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [VADDR-1:0] dmem_word_addr;
    reg  [`XLEN-1:0] dmem_wdata_a;
    reg              illegal_addr;
    reg  [7:0]       byte_strobe;
    wire [2:0]       byte_addr = dmem_full_addr_i[2:0];
    wire             exception;
    

    always @ (*) begin : dmem_strobe_gen
        case (mem_width_1h_i)
            `MEM_WIDTH_1H_BYTE: begin
                illegal_addr      = 1'b0;
                dmem_wdata_a      = { 8{rs2_data_i[7:0]} };
                byte_strobe       = (8'b0000_0001 << byte_addr);
            end
            `MEM_WIDTH_1H_HALF: begin 
                illegal_addr      = (byte_addr[0] == 1'b1);
                dmem_wdata_a      = { 4{rs2_data_i[15:0]} };
                byte_strobe       = (illegal_addr) ? 8'b0 : (8'b0000_0011 << byte_addr);
            end
            `MEM_WIDTH_1H_WORD: begin 
                illegal_addr      = !((byte_addr == 3'b100) || (byte_addr == 3'b000));
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
    
    assign dmem_word_addr = {dmem_full_addr_i[VADDR-1:2], 2'b0};


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 Host Memory Request Driver                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire mem_read  = mem_rd_i & valid;
    wire mem_write = mem_wr_i & valid;

    obi_host_driver #(.DATA_W(`XLEN), .ADDR_W(VADDR)) dmem_obi_host_driver 
    (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),

        .gnt_i    (dmem_gnt_i),
        .rvalid_i (dmem_rvalid_i),

        .stall_i  (stall_i),

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

    assign unalign_store_ex_ao = illegal_addr && mem_write;
    assign unalign_load_ex_ao  = illegal_addr && mem_read;
    assign exception           = illegal_addr && (mem_rd_i || mem_wr_i);


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
        valid_o          <= (stall_i) ? valid_o          : valid && (~exception);
        // Destination Register (rd) 
        rd_data_o        <= (stall_i) ? rd_data_o        : rd_data_i;
        rd_idx_o         <= (stall_i) ? rd_idx_o         : rd_idx_i;
        rd_wr_en_o       <= (stall_i) ? rd_wr_en_o       : rd_wr_en_i;
        rd_wr_src_load_o <= (stall_i) ? rd_wr_src_load_o : rd_wr_src_load_i;
        // Load/Store 
        mem_width_1h_o   <= (stall_i) ? mem_width_1h_o   : mem_width_1h_i;
        mem_sign_o       <= (stall_i) ? mem_sign_o       : mem_sign_i;
        byte_addr_o      <= (stall_i) ? byte_addr_o      : dmem_full_addr_i[2:0];
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
