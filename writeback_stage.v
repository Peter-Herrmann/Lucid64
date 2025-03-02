///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: writeback_stage                                                                  //
// Description: Writeback Stage. Slices up the 64 bit read from memory as needed and controls    //
//              all writes to the register file.                                                 //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: CC-BY-NC-ND-4.0                                                      //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module writeback_stage (
    //======= Clocks, Resets, and Stage Controls ========//
    input                       clk_i,
    input                       rst_ni,
    
    input                       squash_i,
    input                       bubble_i,
    input                       stall_i,

    //============= Memory Pipeline Inputs ==============//
    input                       valid_i,
    // Destination Register (rd)
    input       [`XLEN-1:0]     rd_data_i,
    input       [4:0]           rd_idx_i,
    input                       rd_wr_en_i,
    input                       rd_wr_src_load_i,
    // Data Memory Load Inputs
    input        [`XLEN-1:0]    dmem_rdata_i,
    input        [3:0]          mem_width_1h_i,
    input                       mem_sign_i,
    input        [2:0]          byte_addr_i,

    //============= Register File Controls ==============//
    output wire [`XLEN-1:0]     rd_data_ao,
    output wire [4:0]           rd_idx_ao,
    output wire                 rd_wr_en_ao,

    output wire                 inst_retired_ao,
    output wire                 valid_ao

`ifdef LUCID64_RVFI
    ,
    input [  32 - 1 : 0]         rvfi_insn_i,
    input                        rvfi_trap_i,
    input                        rvfi_intr_i,
    input [   5 - 1 : 0]         rvfi_rs1_addr_i,
    input [   5 - 1 : 0]         rvfi_rs2_addr_i,
    input [`XLEN - 1 : 0]        rvfi_rs1_rdata_i,
    input [`XLEN - 1 : 0]        rvfi_rs2_rdata_i,
    input [`XLEN - 1 : 0]        rvfi_pc_rdata_i,
    input [`XLEN - 1 : 0]        rvfi_pc_wdata_i,
    input [`XLEN   - 1 : 0]      rvfi_mem_addr_i,
    input [`XLEN/8 - 1 : 0]      rvfi_mem_rmask_i,
    input [`XLEN/8 - 1 : 0]      rvfi_mem_wmask_i,
    input [`XLEN   - 1 : 0]      rvfi_mem_rdata_i,
    input [`XLEN   - 1 : 0]      rvfi_mem_wdata_i,

    output reg                   rvfi_valid_o,
    output reg [  64 - 1 : 0]    rvfi_order_o,
    output reg [  32 - 1 : 0]    rvfi_insn_o,
    output reg                   rvfi_trap_o,
    output reg                   rvfi_halt_o,
    output reg                   rvfi_intr_o,
    output reg [2    - 1 : 0]    rvfi_mode_o,
    output reg [2    - 1 : 0]    rvfi_ixl_o,
    output reg [   5 - 1 : 0]    rvfi_rs1_addr_o,
    output reg [   5 - 1 : 0]    rvfi_rs2_addr_o,
    output reg [`XLEN - 1 : 0]   rvfi_rs1_rdata_o,
    output reg [`XLEN - 1 : 0]   rvfi_rs2_rdata_o,
    output reg [   5 - 1 : 0]    rvfi_rd_addr_o,
    output reg [`XLEN - 1 : 0]   rvfi_rd_wdata_o,
    output reg [`XLEN - 1 : 0]   rvfi_pc_rdata_o,
    output reg [`XLEN - 1 : 0]   rvfi_pc_wdata_o,
    output reg [`XLEN   - 1 : 0] rvfi_mem_addr_o,
    output reg [`XLEN/8 - 1 : 0] rvfi_mem_rmask_o,
    output reg [`XLEN/8 - 1 : 0] rvfi_mem_wmask_o,
    output reg [`XLEN   - 1 : 0] rvfi_mem_rdata_o,
    output reg [`XLEN   - 1 : 0] rvfi_mem_wdata_o
`endif
);
    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Validity Tracker                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire valid;

    validity_tracker WB_validity_tracker (
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

    wire [7:0]      bytes [0:7];
    wire [15:0]     halfs [0:3];
    wire [31:0]     words [0:1];
    reg [`XLEN-1:0] load_data_sliced;
    reg             msb;


    assign { bytes[7], bytes[6], bytes[5], bytes[4], 
             bytes[3], bytes[2], bytes[1], bytes[0] } = dmem_rdata_i[63:0];
    assign { halfs[3], halfs[2], halfs[1], halfs[0] } = dmem_rdata_i[63:0];
    assign { words[1], words[0] }                     = dmem_rdata_i[63:0];


    always @ (*) begin
        case (mem_width_1h_i)
            `MEM_WIDTH_1H_BYTE:   begin
                msb              = (mem_sign_i == `MEM_SIGNED) ? bytes[byte_addr_i][7] : 1'b0;
                load_data_sliced = { {56{msb}}, bytes[byte_addr_i]} ;
            end
            `MEM_WIDTH_1H_HALF:   begin
                msb              = (mem_sign_i == `MEM_SIGNED) ? halfs[byte_addr_i[2:1]][15] : 1'b0;
                load_data_sliced = { {48{msb}}, halfs[byte_addr_i[2:1]] };
            end
            `MEM_WIDTH_1H_WORD:   begin
                msb              = (mem_sign_i == `MEM_SIGNED) ? words[byte_addr_i[2]][31] : 1'b0;
                load_data_sliced = { {32{msb}}, words[byte_addr_i[2]] };
            end
            `MEM_WIDTH_1H_DOUBLE: begin
                msb              = dmem_rdata_i[`XLEN-1];
                load_data_sliced = dmem_rdata_i;
            end
            default: begin
                msb              = 1'b0;
                load_data_sliced = 'b0;
            end
        endcase
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  Register File Controls                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Update load instuctions with correct source (alu/pc sources handled in execute) 
    assign rd_data_ao  = (rd_wr_src_load_i) ? load_data_sliced : rd_data_i;
    assign rd_idx_ao   = rd_idx_i;
    assign rd_wr_en_ao = rd_wr_en_i && valid && ~stall_i;

    assign inst_retired_ao = valid && ~stall_i;
    assign valid_ao        = valid;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  RISC-V Formal Interface                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

`ifdef LUCID64_RVFI

    reg [63:0] rvfi_order = '0;

    always @(posedge clk) begin
        if (inst_retired_ao)
            rvfi_order <= rvfi_order + 64'd1;
    end

    always @(*) begin
        rvfi_valid_o      = inst_retired_ao;
        rvfi_order_o      = rvfi_order;
        rvfi_insn_o       = rvfi_insn_i;
        rvfi_trap_o       = rvfi_trap_i;
        rvfi_halt_o       = 1'b0;
        rvfi_intr_o       = rvfi_intr_i;
        rvfi_mode_o       = 2'd3; // Machine mode
        rvfi_ixl_o        = 2'd2; // 64 bit
        rvfi_rs1_addr_o   = rvfi_rs1_addr_i;
        rvfi_rs2_addr_o   = rvfi_rs2_addr_i;
        rvfi_rs1_rdata_o  = rvfi_rs1_rdata_i;
        rvfi_rs2_rdata_o  = rvfi_rs2_rdata_i;
        rvfi_rd_addr_o    = rd_idx_ao;
        rvfi_rd_wdata_o   = rd_data_ao;
        rvfi_pc_rdata_o   = rvfi_pc_rdata_i;
        rvfi_pc_wdata_o   = rvfi_pc_wdata_i;
        rvfi_mem_addr_o   = rvfi_mem_addr_i;
        rvfi_mem_rmask_o  = rvfi_mem_rmask_i;
        rvfi_mem_wmask_o  = rvfi_mem_wmask_i;
        rvfi_mem_rdata_o  = load_data_sliced; // Should this be raw word?
        rvfi_mem_wdata_o  = rvfi_mem_wdata_i;
    end

`endif

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
