///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// Module Name: compressed_decoder                                                               //
// Description: An asyncronous RV64IMAC decoder for 16-bit compressed instructions. Arbitration  //
//              between compressed and non-compressed instrucitons is handled externally         //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: CC-BY-NC-ND-4.0                                                      //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "Lucid64.vh"


module compressed_decoder #(parameter VADDR = 39) (
    input [15:0]            inst_i,
    input   [`XLEN-1:0]     rs1_data_i,
    input   [`XLEN-1:0]     rs2_data_i,
    input [VADDR-1:0]       pc_i,

    output wire [3:0]       mem_width_1h_ao,     
    output wire             mem_sign_ao,            
    output wire             mem_rd_ao,              
    output wire             mem_wr_ao,              

    output reg  [4:0]       rs1_idx_ao,     
    output reg  [4:0]       rs2_idx_ao,     
    output reg  [4:0]       rd_idx_ao,      
    output reg              rs1_used_ao,    
    output reg              rs2_used_ao,    
    output reg              rd_wr_en_ao,    
    output reg  [4:0]       rd_wr_src_1h_ao,

    output reg [`XLEN-1:0]  alu_op_a_ao,
    output reg [`XLEN-1:0]  alu_op_b_ao,
    output wire             alu_uses_rs1_ao,
    output wire             alu_uses_rs2_ao,
    output reg  [5:0]       alu_operation_ao,

    output reg  [5:0]       branch_cond_1h_ao,
    output wire             branch_ao, 
    output wire             ebreak_ao,
    output reg              illegal_inst_ao 
);

    wire [1:0] quadrant    = inst_i[1:0];
    wire [2:0] c_func3     = inst_i[15:13];
    wire [4:0] c_rs1       = inst_i[11:7];
    wire [4:0] c_rs2       = inst_i[6:2];
    wire [4:0] c_rd        = c_rs1;
    wire [4:0] c_rs1_prime = { 2'b01, c_rs1[2:0] };
    wire [4:0] c_rs2_prime = { 2'b01, c_rs2[2:0] };
    wire [4:0] c_rd_prime  = c_rs2_prime; // For formats other than CA
    wire [4:0] ca_rd_prime = c_rs1_prime;

    // opcode signals
    reg addi4spn, addi,     slli,      lw, addiw, li,   lwsp, ld, lui_addi16sp, 
        ldsp,     misc_alu, jr_mv_add, j,  sw,    beqz, swsp, sd, bnez,   sdsp;

     always @(*) begin
        {addi4spn, addi,     slli,      lw, addiw, li,   lwsp, ld, lui_addi16sp, 
         ldsp,     misc_alu, jr_mv_add, j,  sw,    beqz, swsp, sd, bnez,   sdsp} = 'b0;
         illegal_inst_ao = 'b0;

         case ({quadrant, c_func3})
            {`C0, `C_FUNC3_ADDI4SPN}  : addi4spn        = 1'b1;
            {`C0, `C_FUNC3_LW}        : lw              = 1'b1;
            {`C0, `C_FUNC3_LD}        : ld              = 1'b1;
            {`C0, `C_FUNC3_SW}        : sw              = 1'b1;
            {`C0, `C_FUNC3_SD}        : sd              = 1'b1;

            {`C1, `C_FUNC3_ADDI}      : addi            = 1'b1;
            {`C1, `C_FUNC3_ADDIW}     : addiw           = 1'b1;
            {`C1, `C_FUNC3_LI}        : li              = 1'b1;
            {`C1, `C_FUNC3_ADDI16SPN} : lui_addi16sp    = 1'b1;
            {`C1, `C_FUNC3_MISC_ALU}  : misc_alu        = 1'b1;
            {`C1, `C_FUNC3_J}         : j               = 1'b1;
            {`C1, `C_FUNC3_BEQZ}      : beqz            = 1'b1;
            {`C1, `C_FUNC3_BNEZ}      : bnez            = 1'b1;
            
            {`C2, `C_FUNC3_SLLI}      : slli            = 1'b1;
            {`C2, `C_FUNC3_LWSP}      : lwsp            = 1'b1;
            {`C2, `C_FUNC3_LDSP}      : ldsp            = 1'b1;
            {`C2, `C_FUNC3_JR_MV_ADD} : jr_mv_add       = 1'b1;
            {`C2, `C_FUNC3_SWSP}      : swsp            = 1'b1;
            {`C2, `C_FUNC3_SDSP}      : sdsp            = 1'b1;

            default                   : illegal_inst_ao = 1'b1;
         endcase
     end

    wire addi16sp = lui_addi16sp && (c_rs1 == 5'd2);
    wire lui      = lui_addi16sp && (c_rs1 != 5'd2);

    wire mv       = jr_mv_add && ~inst_i[12] && (c_rs2 != 'b0);
    wire add      = jr_mv_add &&  inst_i[12] && (c_rs2 != 'b0);
    wire jr       = jr_mv_add && ~inst_i[12] && (c_rs2 == 'b0);
    wire jalr     = jr_mv_add &&  inst_i[12] && (c_rs2 == 'b0) && (c_rs1 != 'b0);

    wire srli     = misc_alu && (inst_i[11:10] == 2'b00); 
    wire srai     = misc_alu && (inst_i[11:10] == 2'b01); 

    wire andi     = misc_alu && (inst_i[11:10] == 2'b10);

    wire alu_logi = misc_alu && (inst_i[12:10] == 3'b011);
    wire sub      = alu_logi && (inst_i[6:5]   == 2'b00);
    wire alu_xor  = alu_logi && (inst_i[6:5]   == 2'b01);
    wire alu_or   = alu_logi && (inst_i[6:5]   == 2'b10);
    wire alu_and  = alu_logi && (inst_i[6:5]   == 2'b11);

    wire subw     = misc_alu && (inst_i[12:10] == 3'b111) && (inst_i[6:5] == 2'b00);
    wire addw     = misc_alu && (inst_i[12:10] == 3'b111) && (inst_i[6:5] == 2'b01);


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      Load/Store Signals                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    assign mem_width_1h_ao = (lw | sw | lwsp | swsp) ? `MEM_WIDTH_1H_WORD : `MEM_WIDTH_1H_DOUBLE;
    assign mem_sign_ao     = `MEM_SIGNED;
    assign mem_rd_ao       = (lw | ld | lwsp | ldsp);
    assign mem_wr_ao       = (sw | sd | swsp | sdsp);


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              Integer Register File Controls                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(*) begin : register_index_decoder
        case (quadrant)
            `C0: begin 
                rs1_idx_ao  = (addi4spn) ? 5'd2 : c_rs1_prime;
                rs1_used_ao = 1'b1;
                rs2_idx_ao  = c_rs2_prime;
                rs2_used_ao = sw | sd;
                rd_idx_ao   = c_rd_prime;
                rd_wr_en_ao = (~inst_i[15]) && (rd_idx_ao != 'b0);
            end

            `C1: begin
                rs1_idx_ao  = (misc_alu | beqz | bnez) ? c_rs1_prime : c_rs1;
                rs1_used_ao = (misc_alu | beqz | bnez | addi | addiw | addi16sp); 
                rs2_idx_ao  = (beqz | bnez) ? 'b0 : c_rs2_prime;
                rs2_used_ao = misc_alu && (inst_i[11:10] == 'b11);
                rd_idx_ao   = misc_alu ? ca_rd_prime : c_rd;
                rd_wr_en_ao = (misc_alu | ~inst_i[15]) && (rd_idx_ao != 'b0);
            end

            `C2: begin
                rs1_idx_ao  = (lwsp | ldsp | swsp | sdsp) ? 5'd2 : c_rs1;
                rs1_used_ao = slli | jr | jalr | lwsp | ldsp | swsp | sdsp | add;
                rs2_idx_ao  = c_rs2;
                rs2_used_ao = swsp | sdsp | add | mv;  
                rd_idx_ao   = jalr ? 'b1 : c_rd;
                rd_wr_en_ao = (~inst_i[15] | jalr | add | mv) && (rd_idx_ao != 'b0);
            end

            default: begin
                rs1_idx_ao  = 'b0 ;
                rs1_used_ao = 'b0;
                rs2_idx_ao  = 'b0;
                rs2_used_ao = 'b0;
                rd_idx_ao   = 'b0;
                rd_wr_en_ao = 'b0;
            end 
        endcase
    end

    always @(*) begin : rd_wr_src_decoder
        if      (jalr)                   rd_wr_src_1h_ao = `WB_SRC_1H_PC_PLUS_4; 
        else if (lw | ld | lwsp | ldsp)  rd_wr_src_1h_ao = `WB_SRC_1H_MEM;
        else                             rd_wr_src_1h_ao = `WB_SRC_1H_I_ALU; 
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ALU Operation                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Immediates:
    wire [`XLEN-1:0] lsw_uimm  = { 57'b0,         inst_i[5],   inst_i[12:10], inst_i[6], 2'b0 };
    wire [`XLEN-1:0] lsd_uimm  = { 56'b0,         inst_i[6:5], inst_i[12:10], 3'b0 };
    wire [`XLEN-1:0] a_imm  = { {58{inst_i[12]}}, inst_i[12],  inst_i[6:2]};
    wire [`XLEN-1:0] ui_imm = { {46{inst_i[12]}}, inst_i[12],  inst_i[6:2],   12'b0 };
    wire [`XLEN-1:0] s_imm     = { 58'b0,         inst_i[12],  inst_i[6:2]};
    wire [`XLEN-1:0] uimm_lwsp = { 56'b0,         inst_i[3:2], inst_i[12],    inst_i[6:4],  2'b0 };
    wire [`XLEN-1:0] uimm_ldsp = { 55'b0,         inst_i[4:2], inst_i[12],    inst_i[6:5],  3'b0 };
    wire [`XLEN-1:0] uimm_swsp = { 56'b0,         inst_i[8:7], inst_i[12:9],  2'b0 };
    wire [`XLEN-1:0] uimm_sdsp = { 55'b0,         inst_i[9:7], inst_i[12:10], 3'b0 };
    wire [`XLEN-1:0] pc  = { {`XLEN-VADDR{1'b0}}, pc_i};

    wire [`XLEN-1:0] a4_imm  = { 54'b0,               inst_i[10:7],  inst_i[12:11], inst_i[5],
                                  inst_i[6], 2'b0 };

    wire [`XLEN-1:0] a16_imm = { {54{inst_i[12]}},    inst_i[12],    inst_i[4:3],   inst_i[5], 
                                  inst_i[2],          inst_i[6], 4'b0 };

    wire [`XLEN-1:0] j_imm     = { {52{inst_i[12]}},  inst_i[12],    inst_i[8],     inst_i[10:9],
                                  inst_i[6],          inst_i[7],     inst_i[2],     inst_i[11], 
                                  inst_i[5:3],        1'b0 };

    wire [`XLEN-1:0] b_imm     = { {55{inst_i[12]}},  inst_i[12],    inst_i[6:5],   inst_i[2],
                                  inst_i[11:10],      inst_i[4:3],   1'b0 };



    always @(*) begin
        if  (alu_uses_rs1_ao)        alu_op_a_ao = rs1_data_i;
        else if         (lui)        alu_op_a_ao = ui_imm;
        else if           (j)        alu_op_a_ao = j_imm;
        else if (beqz | bnez)        alu_op_a_ao = b_imm;
        else if     (mv | li)        alu_op_a_ao = 'b0;
        else                         alu_op_a_ao = rs1_data_i;
    end

    always @(*) begin
        if (alu_uses_rs2_ao)         alu_op_b_ao = rs2_data_i;
        else if    (addi4spn)        alu_op_b_ao = a4_imm;
        else if (j | beqz | bnez)    alu_op_b_ao = pc;
        else if (lw | sw)            alu_op_b_ao = lsw_uimm;
        else if (ld | sd)            alu_op_b_ao = lsd_uimm;
        else if (srli | srai | slli) alu_op_b_ao = s_imm;
        else if (addi16sp)           alu_op_b_ao = a16_imm;
        else if (andi | addi | 
                 li | addiw)         alu_op_b_ao = a_imm;
        else if (lwsp)               alu_op_b_ao = uimm_lwsp;
        else if (ldsp)               alu_op_b_ao = uimm_ldsp;
        else if (swsp)               alu_op_b_ao = uimm_swsp;
        else if (sdsp)               alu_op_b_ao = uimm_sdsp;
        else                         alu_op_b_ao = rs2_data_i;
    end

    always @(*) begin
        if      (srli)               alu_operation_ao = `ALU_OP_SRL;
        else if (srai)               alu_operation_ao = `ALU_OP_SRA;
        else if (slli)               alu_operation_ao = `ALU_OP_SLL;
        else if (andi | alu_and)     alu_operation_ao = `ALU_OP_AND;
        else if (alu_xor)            alu_operation_ao = `ALU_OP_XOR;
        else if (alu_or)             alu_operation_ao = `ALU_OP_OR;
        else if (sub)                alu_operation_ao = `ALU_OP_SUB;
        else if (subw)               alu_operation_ao = `ALU_OP_SUBW;
        else if (addw | addiw)       alu_operation_ao = `ALU_OP_ADDW;
        else if (lui)                alu_operation_ao = `ALU_OP_PASS;
        else                         alu_operation_ao = `ALU_OP_ADD;
    end

    assign alu_uses_rs1_ao = rs1_used_ao && !(beqz | bnez);
    assign alu_uses_rs2_ao = rs2_used_ao && !(sw | sd | swsp | sdsp);


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   Flow Control and Exceptions                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    always @(*) begin : conditional_branch_decoder
        if      (beqz) branch_cond_1h_ao = `BR_OP_1H_BEQ;
        else if (bnez) branch_cond_1h_ao = `BR_OP_1H_BNE; 
        else           branch_cond_1h_ao = 'b0;
    end
    
    assign branch_ao = j | jr | jalr;
    assign ebreak_ao = jr_mv_add && inst_i[12] && (c_rs2 == 'b0) && (c_rs1 == 'b0);
    

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
