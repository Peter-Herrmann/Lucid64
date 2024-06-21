///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: decoder                                                                          //
// Description: An asyncronous RV64IMA_Zicsr_Zifencei decoder.                                   //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: CC-BY-NC-ND-4.0                                                      //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module decoder #(parameter VADDR = 39) (
    input [31:0]            inst_i,

    input [`XLEN-1:0]       rs1_data_i,
    input [`XLEN-1:0]       rs2_data_i,
    input [VADDR-1:0]       pc_i,

    input                   csr_rd_en_i,
    input                   sys_csr_i,

    output wire [`XLEN-1:0] csr_imm_ao,

    output reg  [3:0]       mem_width_1h_ao,     
    output wire             mem_sign_ao,            
    output wire             mem_rd_ao,              
    output wire             mem_wr_ao,              

    output wire [4:0]       rs1_idx_ao,     
    output wire [4:0]       rs2_idx_ao,     
    output wire [4:0]       rd_idx_ao,      
    output wire             rs1_used_ao,    
    output wire             rs2_used_ao,    
    output wire             rd_wr_en_ao,    
    output reg  [4:0]       rd_wr_src_1h_ao,

    output wire [`XLEN-1:0] alu_op_a_ao,
    output wire [`XLEN-1:0] alu_op_b_ao,
    output wire             alu_uses_rs1_ao,
    output wire             alu_uses_rs2_ao,
    output wire [5:0]       alu_operation_ao,

    output reg  [5:0]       branch_cond_1h_ao,
    output wire             branch_ao, 
    output wire             ebreak_ao,
    output wire             fencei_ao,
    output wire             ecall_ex_ao,    
    output wire             mret_ao,        
    output wire             wait_for_int_ao
);

    wire [6:0]  opcode = inst_i[6:0];
    wire [2:0]  func3  = inst_i[14:12];
    wire [11:0] func12 = inst_i[31:20];


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Load/Store Signals                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(*) begin : mem_width_decoder
        case (func3[1:0])
            `MEM_WIDTH_BYTE     : mem_width_1h_ao = `MEM_WIDTH_1H_BYTE;
            `MEM_WIDTH_HALF     : mem_width_1h_ao = `MEM_WIDTH_1H_HALF;
            `MEM_WIDTH_WORD     : mem_width_1h_ao = `MEM_WIDTH_1H_WORD;
            `MEM_WIDTH_DOUBLE   : mem_width_1h_ao = `MEM_WIDTH_1H_DOUBLE;
            default             : mem_width_1h_ao = 'b0;
        endcase
    end

    assign mem_wr_ao = (opcode == `OPCODE_STORE);
    assign mem_rd_ao = (opcode == `OPCODE_LOAD);
    assign mem_sign_ao = func3[2];
    

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              Integer Register File Controls                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    wire M_alu_sel = inst_i[25];

    assign rs1_used_ao = (opcode != `OPCODE_LUI)   && 
                         (opcode != `OPCODE_AUIPC) && 
                         (opcode != `OPCODE_JAL);

    assign rs2_used_ao = (opcode == `OPCODE_BRANCH) || 
                         (opcode == `OPCODE_STORE)  || 
                         (opcode == `OPCODE_OP_W)   ||
                         (opcode == `OPCODE_OP);

    assign rd_wr_en_ao = (csr_rd_en_i) || 
                         ( (opcode    != `OPCODE_BRANCH) && 
                           (opcode    != `OPCODE_STORE)  && 
                           (rd_idx_ao != 'b0) ); 

    always @(*) begin : rd_wr_src_decoder
        case (opcode)
            `OPCODE_JAL    : rd_wr_src_1h_ao = `WB_SRC_1H_PC_PLUS_4; 
            `OPCODE_JALR   : rd_wr_src_1h_ao = `WB_SRC_1H_PC_PLUS_4;
            `OPCODE_LOAD   : rd_wr_src_1h_ao = `WB_SRC_1H_MEM;
            `OPCODE_OP     : rd_wr_src_1h_ao = M_alu_sel ? `WB_SRC_1H_M_ALU : `WB_SRC_1H_I_ALU;
            `OPCODE_OP_W   : rd_wr_src_1h_ao = M_alu_sel ? `WB_SRC_1H_M_ALU : `WB_SRC_1H_I_ALU;
            `OPCODE_SYSTEM : rd_wr_src_1h_ao = sys_csr_i ? `WB_SRC_CSR      : `WB_SRC_1H_I_ALU;
            default        : rd_wr_src_1h_ao = `WB_SRC_1H_I_ALU; 
        endcase
    end

    assign rs1_idx_ao = inst_i[19:15];
    assign rs2_idx_ao = inst_i[24:20];
    assign rd_idx_ao  = inst_i[11:7];


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ALU Operation                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    alu_decoder #(.VADDR(VADDR)) uncompressed_alu_decoder (
        .inst_i             (inst_i),
        .rs1_data_i         (rs1_data_i),
        .rs2_data_i         (rs2_data_i),
        .pc_i               (pc_i),

        .csr_imm_ao         (csr_imm_ao),

        .alu_op_a_ao        (alu_op_a_ao),
        .alu_op_b_ao        (alu_op_b_ao),
        .alu_uses_rs1_ao    (alu_uses_rs1_ao),
        .alu_uses_rs2_ao    (alu_uses_rs2_ao),

        .alu_operation_ao   (alu_operation_ao)
    );


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   Flow Control and Exceptions                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(*) begin
        branch_cond_1h_ao = 'b0;
        if (opcode == `OPCODE_BRANCH) begin
            case (func3)
                `BR_OP_BEQ    : branch_cond_1h_ao = `BR_OP_1H_BEQ;     
                `BR_OP_BNE    : branch_cond_1h_ao = `BR_OP_1H_BNE; 
                `BR_OP_BLT    : branch_cond_1h_ao = `BR_OP_1H_BLT; 
                `BR_OP_BGE    : branch_cond_1h_ao = `BR_OP_1H_BGE; 
                `BR_OP_BLTU   : branch_cond_1h_ao = `BR_OP_1H_BLTU; 
                `BR_OP_BGEU   : branch_cond_1h_ao = `BR_OP_1H_BGEU;     
                default       : branch_cond_1h_ao = 'b0;
            endcase
        end
    end
    
    assign branch_ao       = (opcode == `OPCODE_JAL) || (opcode == `OPCODE_JALR);

    // sys_priv is only true for uncompressed instructions (Quadrant 2'b11)
    wire   sys_priv        = (opcode == `OPCODE_SYSTEM)   && (func3 == `SYSTEM_OP_PRIV);
    assign fencei_ao       = (opcode == `OPCODE_MISC_MEM) && (func3 == `MISC_MEM_FENCE_I);
    assign ecall_ex_ao     = sys_priv && func12 == `FUNC12_ECALL;         
    assign mret_ao         = sys_priv && func12 == `FUNC12_MRET;
    assign wait_for_int_ao = sys_priv && func12 == `FUNC12_WFI;
    assign ebreak_ao       = sys_priv && func12 == `FUNC12_EBREAK;


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
