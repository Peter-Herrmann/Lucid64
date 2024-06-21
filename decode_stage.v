///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: decode_stage                                                                     //
// Description: Decode Stage. A single-instruction synchronous decoder for an                    //
//                            RV64IMAC_Zicsr_Zifencei hart.                                      //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module decode_stage #(parameter VADDR = 39) (
    //======= Clocks, Resets, and Stage Controls ========//
    input                  clk_i,
    input                  rst_ni,
    
    input                  squash_i,
    input                  bubble_i,
    input                  stall_i,

    //=============== Fetch Stage Inputs ================//
    input [VADDR-1:0]      pc_i,
    input [VADDR-1:0]      next_pc_i,
    input                  valid_i,
    // Instruction from memory
    input       [31:0]     inst_i,

    // ============== Fetch Stage Feedback ==============//
    output wire            compressed_instr_ao,

    //======= Register File Async Read Interface ========//
    output wire [4:0]      rs1_idx_ao,
    output wire [4:0]      rs2_idx_ao,
    input [`XLEN-1:0]      rs1_data_i,
    input [`XLEN-1:0]      rs2_data_i,

    //=============== CSR Read Interface ================//
    output wire [11:0]     csr_addr_ao,
    output wire            csr_rd_en_ao,
    // CSR Load Use Hazard Inputs
    input       [11:0]     EXE_csr_addr_i,
    input                  EXE_csr_wr_en_i,
    output wire            csr_load_use_haz_ao,

    //================ Pipeline Outputs =================//
    output reg          valid_o,
    // Register Source 1 (rs1)
    output reg  [4:0]      rs1_idx_o,
    output reg             rs1_used_o,
    output reg [`XLEN-1:0] rs1_data_o,
    // Register Source 2 (rs2)
    output reg  [4:0]      rs2_idx_o,
    output reg             rs2_used_o,
    output reg [`XLEN-1:0] rs2_data_o,
    // Destination Register (rd)
    output reg  [4:0]      rd_idx_o,
    output reg             rd_wr_en_o,
    output reg  [4:0]      rd_wr_src_1h_o,
    // ALU Operation and Operands
    output reg  [5:0]      alu_operation_o,
    output reg [`XLEN-1:0] alu_op_a_o,
    output reg [`XLEN-1:0] alu_op_b_o,
    output reg             alu_uses_rs1_o,
    output reg             alu_uses_rs2_o,
    // Load/Store
    output reg  [3:0]      mem_width_1h_o,
    output reg             mem_rd_o,
    output reg             mem_wr_o,
    output reg             mem_sign_o,
    // Flow Control
    output reg             branch_o,
    output reg [VADDR-1:0] pc_o,
    output reg [VADDR-1:0] next_pc_o,
    output reg  [5:0]      br_cond_1h_o,
    // CSR Control
    output reg             csr_wr_en_o,
    output reg [2:0]       csr_op_1h_o,
    output reg [11:0]      csr_addr_o,
    // Traps and Exceptions
    output reg             ecall_ex_o,
    output reg             ebreak_ex_o,
    output reg             illegal_inst_ex_o,
    output reg             mret_o,
    output reg             wait_for_int_o,
    output reg             fencei_o

    );
    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Validity Tracker                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire valid;

    validity_tracker DCD_validity_tracker (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),

        .valid_i        (valid_i),
        
        .squash_i       (squash_i),
        .bubble_i       (bubble_i),
        .stall_i        (stall_i),

        .valid_ao       (valid)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                Standard Instruction Decoder                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    // Load/Store Controls
    wire [3:0]       mem_width_1h_uncompr;
    wire             mem_sign_uncompr, mem_rd_uncompr, mem_wr_uncompr;
    // Register File Controls
    wire [4:0]       rs1_idx_uncompr,  rs2_idx_uncompr,  rd_idx_uncompr;
    wire             rs1_used_uncompr, rs2_used_uncompr, rd_wr_en_uncompr;
    wire [4:0]       rd_wr_src_1h_uncompr;
    // ALU Operation
    wire [`XLEN-1:0] alu_op_a_uncompr,     alu_op_b_uncompr;
    wire             alu_uses_rs1_uncompr, alu_uses_rs2_uncompr;
    wire [5:0]       alu_operation_uncompr;
    // Flow Control and Exceptions
    wire [5:0]       branch_cond_1h_uncompr;
    wire             branch_uncompr, ebreak_uncompr, ecall_ex, mret, wait_for_int, fencei;
    // CSR Signals
    wire             csr_rd_en, sys_csr;
    wire [`XLEN-1:0] csr_immed;
    
    decoder #(.VADDR(VADDR)) i_standard_decoder(
        .inst_i            (inst_i),
        .pc_i              (pc_i),
        .rs1_data_i        (rs1_data_i),
        .rs2_data_i        (rs2_data_i),
        // CSR Controls
        .csr_rd_en_i       (csr_rd_en),
        .sys_csr_i         (sys_csr),
        .csr_imm_ao        (csr_immed),
        // Load/Store Controls
        .mem_width_1h_ao   (mem_width_1h_uncompr),     
        .mem_sign_ao       (mem_sign_uncompr),            
        .mem_rd_ao         (mem_rd_uncompr),              
        .mem_wr_ao         (mem_wr_uncompr),      
        // Register File Controls
        .rs1_idx_ao        (rs1_idx_uncompr),     
        .rs2_idx_ao        (rs2_idx_uncompr),     
        .rd_idx_ao         (rd_idx_uncompr),      
        .rs1_used_ao       (rs1_used_uncompr),    
        .rs2_used_ao       (rs2_used_uncompr),    
        .rd_wr_en_ao       (rd_wr_en_uncompr),    
        .rd_wr_src_1h_ao   (rd_wr_src_1h_uncompr),
        // ALU Operation
        .alu_op_a_ao       (alu_op_a_uncompr),
        .alu_op_b_ao       (alu_op_b_uncompr),
        .alu_uses_rs1_ao   (alu_uses_rs1_uncompr),
        .alu_uses_rs2_ao   (alu_uses_rs2_uncompr),
        .alu_operation_ao  (alu_operation_uncompr),
        // Flow Control and Exceptions
        .branch_cond_1h_ao (branch_cond_1h_uncompr),
        .branch_ao         (branch_uncompr), 
        .ebreak_ao         (ebreak_uncompr),
        .fencei_ao         (fencei),
        .ecall_ex_ao       (ecall_ex),
        .mret_ao           (mret),
        .wait_for_int_ao   (wait_for_int) 
    );

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                               Compressed Instruction Decoder                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [1:0]       quadrant     = inst_i[1:0];
    wire             compressed   = (quadrant != 2'b11);
    // Load/Store Controls
    wire [3:0]       mem_width_1h_compr;
    wire             mem_sign_compr, mem_rd_compr, mem_wr_compr;
    // Register File Controls
    wire [4:0]       rs1_idx_compr,  rs2_idx_compr,  rd_idx_compr;
    wire             rs1_used_compr, rs2_used_compr, rd_wr_en_compr;
    wire [4:0]       rd_wr_src_1h_compr;
    // ALU Operation
    wire [`XLEN-1:0] alu_op_a_compr,     alu_op_b_compr;
    wire             alu_uses_rs1_compr, alu_uses_rs2_compr;
    wire [5:0]       alu_operation_compr;
    // Flow Control and Exceptions
    wire [5:0]       branch_cond_1h_compr;
    wire             branch_compr, ebreak_compr, illegal_inst_compr;
    
    
    compressed_decoder #(.VADDR(VADDR)) i_compressed_decoder(
        .inst_i            (inst_i[15:0]),
        .pc_i              (pc_i),
        .rs1_data_i        (rs1_data_i),
        .rs2_data_i        (rs2_data_i),
        // Load/Store Controls
        .mem_width_1h_ao   (mem_width_1h_compr),     
        .mem_sign_ao       (mem_sign_compr),            
        .mem_rd_ao         (mem_rd_compr),              
        .mem_wr_ao         (mem_wr_compr),      
        // Register File Controls
        .rs1_idx_ao        (rs1_idx_compr),     
        .rs2_idx_ao        (rs2_idx_compr),     
        .rd_idx_ao         (rd_idx_compr),      
        .rs1_used_ao       (rs1_used_compr),    
        .rs2_used_ao       (rs2_used_compr),    
        .rd_wr_en_ao       (rd_wr_en_compr),    
        .rd_wr_src_1h_ao   (rd_wr_src_1h_compr),
        // ALU Operation
        .alu_op_a_ao       (alu_op_a_compr),
        .alu_op_b_ao       (alu_op_b_compr),
        .alu_uses_rs1_ao   (alu_uses_rs1_compr),
        .alu_uses_rs2_ao   (alu_uses_rs2_compr),
        .alu_operation_ao  (alu_operation_compr),
        // Flow Control and Exceptions
        .branch_cond_1h_ao (branch_cond_1h_compr),
        .branch_ao         (branch_compr), 
        .ebreak_ao         (ebreak_compr),
        .illegal_inst_ao   (illegal_inst_compr) 
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                       Compressed vs Uncompressed Decoder Multiplexer                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Load/Store Controls
    wire       mem_wr          = compressed ? mem_wr_compr         : mem_wr_uncompr;
    wire       mem_rd          = compressed ? mem_rd_compr         : mem_rd_uncompr;
    wire       mem_sign        = compressed ? mem_sign_compr       : mem_sign_uncompr;
    wire [3:0] mem_width_1h    = compressed ? mem_width_1h_compr   : mem_width_1h_uncompr;
    // Register File Controls
    wire [4:0] rs1_idx         = compressed ? rs1_idx_compr        : rs1_idx_uncompr;
    wire [4:0] rs2_idx         = compressed ? rs2_idx_compr        : rs2_idx_uncompr;    
    wire [4:0] rd_idx          = compressed ? rd_idx_compr         : rd_idx_uncompr;
    wire       rs1_used        = compressed ? rs1_used_compr       : rs1_used_uncompr;
    wire       rs2_used        = compressed ? rs2_used_compr       : rs2_used_uncompr;
    wire       rd_wr_en        = compressed ? rd_wr_en_compr       : rd_wr_en_uncompr;
    wire [4:0] rd_wr_src_1h    = compressed ? rd_wr_src_1h_compr   : rd_wr_src_1h_uncompr;
    // ALU Operation
    wire [`XLEN-1:0] alu_op_a  = compressed ? alu_op_a_compr       : alu_op_a_uncompr;
    wire [`XLEN-1:0] alu_op_b  = compressed ? alu_op_b_compr       : alu_op_b_uncompr;
    wire        alu_uses_rs1   = compressed ? alu_uses_rs1_compr   : alu_uses_rs1_uncompr;
    wire        alu_uses_rs2   = compressed ? alu_uses_rs2_compr   : alu_uses_rs2_uncompr;
    wire [5:0]  alu_operation  = compressed ? alu_operation_compr  : alu_operation_uncompr;
    // Flow Control and Exceptions
    wire [5:0] branch_cond_1h  = compressed ? branch_cond_1h_compr : branch_cond_1h_uncompr;
    wire       branch          = compressed ? branch_compr         : branch_uncompr;     
    wire       ebreak_ex       = compressed ? ebreak_compr         : ebreak_uncompr;
    // Program Counter Controls
    wire [VADDR-1:0] next_pc   = compressed ? (next_pc_i - 2) : next_pc_i;
    assign compressed_instr_ao = compressed && valid;

    assign rs1_idx_ao = rs1_idx;
    assign rs2_idx_ao = rs2_idx;


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                            Control Status Register Operations                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire [6:0] opcode    = inst_i[6:0];
    wire [2:0] func3     = inst_i[14:12];
    wire [11:0] csr_addr = inst_i[31:20];
    reg  [2:0]  csr_op_1h;

    assign sys_csr   = (opcode == `OPCODE_SYSTEM)  && (func3 != `SYSTEM_OP_PRIV);
    wire   csr_op_rw = (func3 == `SYSTEM_OP_CSRRW) || (func3 == `SYSTEM_OP_CSRRWI);

    // CSR read/write controls
    wire   csr_wr_en           = sys_csr && ( csr_op_rw || csr_immed != 'b0) && valid;
    assign csr_rd_en           = sys_csr && (!csr_op_rw || rd_idx    != 'b0);
    assign csr_rd_en_ao        = csr_rd_en && valid;
    assign csr_addr_ao         = csr_addr;
    assign csr_load_use_haz_ao = (csr_addr == EXE_csr_addr_i) && EXE_csr_wr_en_i && csr_rd_en;
    
    // CSR ALU Operations
    always @(*) begin
        if (sys_csr) begin
            case (func3)
                `SYSTEM_OP_CSRRW : csr_op_1h = `CSR_ALU_OP_1H_RW;
                `SYSTEM_OP_CSRRWI: csr_op_1h = `CSR_ALU_OP_1H_RW; 
                `SYSTEM_OP_CSRRS : csr_op_1h = `CSR_ALU_OP_1H_RS;
                `SYSTEM_OP_CSRRSI: csr_op_1h = `CSR_ALU_OP_1H_RS; 
                `SYSTEM_OP_CSRRC : csr_op_1h = `CSR_ALU_OP_1H_RC;
                `SYSTEM_OP_CSRRCI: csr_op_1h = `CSR_ALU_OP_1H_RC; 
                default          : csr_op_1h = 'b0;
            endcase
        end else 
            csr_op_1h = 'b0;
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                Illegal Instruction Detector                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire illegal_inst_ex = compressed ? illegal_inst_compr : 'b0; // TODO: make complete illegal instruction logic


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //        ____  _            _ _              ____            _     _                        //
    //       |  _ \(_)_ __   ___| (_)_ __   ___  |  _ \ ___  __ _(_)___| |_ ___ _ __ ___         //
    //       | |_) | | '_ \ / _ \ | | '_ \ / _ \ | |_) / _ \/ _` | / __| __/ _ \ '__/ __|        //
    //       |  __/| | |_) |  __/ | | | | |  __/ |  _ <  __/ (_| | \__ \ ||  __/ |  \__ \        //
    //       |_|   |_| .__/ \___|_|_|_| |_|\___| |_| \_\___|\__, |_|___/\__\___|_|  |___/        //
    //               |_|                                    |___/                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk_i) begin : decode_pipeline_registers
    // On stall, all outputs do not change.
        valid_o             <= (stall_i) ? valid_o           : valid;
        // Register Source 1 (rs1)
        rs1_idx_o           <= (stall_i) ? rs1_idx_o         : (rs1_used ? rs1_idx : 'b0);
        rs1_used_o          <= (stall_i) ? rs1_used_o        : rs1_used;
        rs1_data_o          <= (stall_i) ? rs1_data_o        : rs1_data_i;
        // Register Source 2 (rs2)
        rs2_idx_o           <= (stall_i) ? rs2_idx_o         : (rs2_used ? rs2_idx : 'b0);
        rs2_used_o          <= (stall_i) ? rs2_used_o        : rs2_used;
        rs2_data_o          <= (stall_i) ? rs2_data_o        : rs2_data_i;
        // Destination Register (rd)
        rd_idx_o            <= (stall_i) ? rd_idx_o          : rd_idx;
        rd_wr_en_o          <= (stall_i) ? rd_wr_en_o        : rd_wr_en;
        rd_wr_src_1h_o      <= (stall_i) ? rd_wr_src_1h_o    : rd_wr_src_1h;
        // ALU Operation and Operands
        alu_operation_o     <= (stall_i) ? alu_operation_o   : alu_operation;
        alu_op_a_o          <= (stall_i) ? alu_op_a_o        : alu_op_a;
        alu_op_b_o          <= (stall_i) ? alu_op_b_o        : alu_op_b;
        alu_uses_rs1_o      <= (stall_i) ? alu_uses_rs1_o    : alu_uses_rs1;
        alu_uses_rs2_o      <= (stall_i) ? alu_uses_rs2_o    : alu_uses_rs2;
        // Load/Store
        mem_width_1h_o      <= (stall_i) ? mem_width_1h_o    : mem_width_1h;
        mem_rd_o            <= (stall_i) ? mem_rd_o          : mem_rd;
        mem_wr_o            <= (stall_i) ? mem_wr_o          : mem_wr;
        mem_sign_o          <= (stall_i) ? mem_sign_o        : mem_sign;
        // Flow Control     
        branch_o            <= (stall_i) ? branch_o          : branch;
        pc_o                <= (stall_i) ? pc_o              : pc_i;
        next_pc_o           <= (stall_i) ? next_pc_o         : next_pc;
        br_cond_1h_o        <= (stall_i) ? br_cond_1h_o      : branch_cond_1h;
        // CSR Control
        csr_wr_en_o         <= (stall_i) ? csr_wr_en_o       : csr_wr_en;
        csr_op_1h_o         <= (stall_i) ? csr_op_1h_o       : csr_op_1h;
        csr_addr_o          <= (stall_i) ? csr_addr_o        : csr_addr;
        // Traps and Exceptions
        ecall_ex_o          <= (stall_i) ? ecall_ex_o        : ecall_ex;
        ebreak_ex_o         <= (stall_i) ? ebreak_ex_o       : ebreak_ex;
        illegal_inst_ex_o   <= (stall_i) ? illegal_inst_ex_o : illegal_inst_ex;
        mret_o              <= (stall_i) ? mret_o            : mret;
        wait_for_int_o      <= (stall_i) ? wait_for_int_o    : wait_for_int;
        fencei_o            <= (stall_i) ? fencei_o          : fencei;
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
