///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// File Name  : Lucid64.vh                                                                       //
// Description: Header containing definitions used throughout the Lucid64 core.                  //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`ifndef LUCID64_VH
`define LUCID64_VH


///////////////////////////////////////////////////////////////////////////////////////////////////
//                                     Program Counter Defines                                   //
///////////////////////////////////////////////////////////////////////////////////////////////////

// Program Counter Source
`define PC_SRC_NO_BRANCH    1'b0
`define PC_SRC_BRANCH       1'b1

`define RESET_ADDR          64'h0

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                        Load Store Defines                                     //
///////////////////////////////////////////////////////////////////////////////////////////////////

// Memory Width { func3[1:0] }
`define MEM_WIDTH_BYTE      2'b00
`define MEM_WIDTH_HALF      2'b01
`define MEM_WIDTH_WORD      2'b10
`define MEM_WIDTH_DOUBLE    2'b11

// Memory Width (1 hot)
`define MEM_WIDTH_1H_BYTE   4'b0001
`define MEM_WIDTH_1H_HALF   4'b0010
`define MEM_WIDTH_1H_WORD   4'b0100
`define MEM_WIDTH_1H_DOUBLE 4'b1000

// Memory Sign { func3[2] }
`define MEM_SIGNED          1'b0
`define MEM_UNSIGNED        1'b1

`define MEM_PHASE_ADDR      1'b0
`define MEM_PHASE_RESP      1'b1

///////////////////////////////////////////////////////////////////////////////////////////////////
//                             Register File Writeback Source Defines                            //
///////////////////////////////////////////////////////////////////////////////////////////////////

// Register File Writeback Source (1 Hot)
`define WB_SRC_1H_ALU       3'b001
`define WB_SRC_1H_MEM       3'b010
`define WB_SRC_1H_PC_PLUS_4 3'b100


///////////////////////////////////////////////////////////////////////////////////////////////////
//                                  Branch Condition Code Defines                                //
///////////////////////////////////////////////////////////////////////////////////////////////////

// Branch Condition Codes { func3 }
`define BR_OP_BEQ           3'b000
`define BR_OP_BNE           3'b001
`define BR_OP_BLT           3'b100
`define BR_OP_BGE           3'b101
`define BR_OP_BLTU          3'b110
`define BR_OP_BGEU          3'b111

// Branch Condition Codes (1 Hot)
`define BR_OP_1H_BEQ        6'b000001
`define BR_OP_1H_BNE        6'b000010
`define BR_OP_1H_BLT        6'b000100
`define BR_OP_1H_BGE        6'b001000
`define BR_OP_1H_BLTU       6'b010000
`define BR_OP_1H_BGEU       6'b100000


///////////////////////////////////////////////////////////////////////////////////////////////////
//                                          OPCODE Defines                                       //
///////////////////////////////////////////////////////////////////////////////////////////////////

// Opcodes { opcode[6:0] }
`define OPCODE_LUI          7'b0110111
`define OPCODE_AUIPC        7'b0010111
`define OPCODE_JAL          7'b1101111
`define OPCODE_JALR         7'b1100111
`define OPCODE_BRANCH       7'b1100011
`define OPCODE_LOAD         7'b0000011
`define OPCODE_STORE        7'b0100011
`define OPCODE_OP_IMM       7'b0010011
`define OPCODE_OP           7'b0110011
`define OPCODE_SYSTEM       7'b1110011
// RV64I Opcodes
`define OPCODE_OP_IMM_W     7'b0011011
`define OPCODE_OP_W         7'b0111011


///////////////////////////////////////////////////////////////////////////////////////////////////
//                                           ALU Defines                                         //
///////////////////////////////////////////////////////////////////////////////////////////////////

// ALU Codes { func7[5], func3, opcode[3] }
`define ALU_OP_ADD          5'b00000
`define ALU_OP_SLL          5'b00010
`define ALU_OP_SLT          5'b00100
`define ALU_OP_SLTU         5'b00110
`define ALU_OP_XOR          5'b01000
`define ALU_OP_SRL          5'b01010
`define ALU_OP_OR           5'b01100
`define ALU_OP_AND          5'b01110
`define ALU_OP_SUB          5'b10000
`define ALU_OP_SRA          5'b11010
`define ALU_OP_PASS         5'b11110
// RV64I W (32 bit) opcodes
`define ALU_OP_ADDW         5'b00001
`define ALU_OP_SLLW         5'b00011
`define ALU_OP_SRLW         5'b01011
`define ALU_OP_SUBW         5'b10001
`define ALU_OP_SRAW         5'b11011

// ALU One-Hot Codes
`define ALU_1H_ADD          16'b0000000000000001
`define ALU_1H_SLL          16'b0000000000000010
`define ALU_1H_SLT          16'b0000000000000100
`define ALU_1H_SLTU         16'b0000000000001000
`define ALU_1H_XOR          16'b0000000000010000
`define ALU_1H_SRL          16'b0000000000100000
`define ALU_1H_OR           16'b0000000001000000
`define ALU_1H_AND          16'b0000000010000000
`define ALU_1H_SUB          16'b0000000100000000
`define ALU_1H_SRA          16'b0000001000000000
`define ALU_1H_PASS         16'b0000010000000000
// RV64I W (32 bit) opcodes
`define ALU_1H_ADDW         16'b0000100000000000
`define ALU_1H_SLLW         16'b0001000000000000
`define ALU_1H_SRLW         16'b0010000000000000
`define ALU_1H_SUBW         16'b0100000000000000
`define ALU_1H_SRAW         16'b1000000000000000

// ALU Operand A
`define ALU_A_SRC_RS1       2'b00
`define ALU_A_SRC_U_IMMED   2'b01
`define ALU_A_SRC_J_IMMED   2'b10
`define ALU_A_SRC_B_IMMED   2'b11

// ALU Operand B
`define ALU_B_SRC_RS2       2'b00
`define ALU_B_SRC_I_IMMED   2'b01
`define ALU_B_SRC_S_IMMED   2'b10
`define ALU_B_SRC_PC        2'b11


`endif // LUCID64_VH


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
