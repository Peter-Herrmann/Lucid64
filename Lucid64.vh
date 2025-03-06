///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// File Name  : Lucid64.vh                                                                       //
// Description: Header containing definitions used throughout the Lucid64 core.                  //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: CC-BY-NC-ND-4.0                                                      //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`ifndef LUCID64_VH
`define LUCID64_VH

`define TODO_DUMMY '0 // Dummy value for development - remove before release
// `define LUCID64_RVFI

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                     Architectural Constants                                   //
///////////////////////////////////////////////////////////////////////////////////////////////////

`define XLEN            64
`define IALIGN_MASK     ( ~('b1) )

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
`define WB_SRC_1H_I_ALU     5'b00001
`define WB_SRC_1H_MEM       5'b00010
`define WB_SRC_1H_PC_PLUS_4 5'b00100
`define WB_SRC_1H_M_ALU     5'b01000
`define WB_SRC_CSR          5'b10000


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
// Zifencei Opcode
`define OPCODE_MISC_MEM     7'b0001111


///////////////////////////////////////////////////////////////////////////////////////////////////
//                                       System Op Defines                                       //
///////////////////////////////////////////////////////////////////////////////////////////////////

`define SYSTEM_OP_PRIV      3'b000
`define SYSTEM_OP_CSRRW     3'b001
`define SYSTEM_OP_CSRRS     3'b010
`define SYSTEM_OP_CSRRC     3'b011
`define SYSTEM_OP_CSRRWI    3'b101
`define SYSTEM_OP_CSRRSI    3'b110
`define SYSTEM_OP_CSRRCI    3'b111

`define CSR_ALU_OP_1H_RW    3'b001
`define CSR_ALU_OP_1H_RS    3'b010
`define CSR_ALU_OP_1H_RC    3'b100

`define FUNC12_ECALL        12'b0000000_00000
`define FUNC12_EBREAK       12'b0000000_00001
`define FUNC12_MRET         12'b0011000_00010
`define FUNC12_SRET         12'b0001000_00010
`define FUNC12_WFI          12'b0001000_00101


///////////////////////////////////////////////////////////////////////////////////////////////////
//                                     Compressed Op Defines                                     //
///////////////////////////////////////////////////////////////////////////////////////////////////

// Quadrant Defines
`define C0 2'b00
`define C1 2'b01
`define C2 2'b10

// Quadrant C0 Defines
`define C_FUNC3_ADDI4SPN  3'b000
`define C_FUNC3_LW        3'b010
`define C_FUNC3_LD        3'b011
`define C_FUNC3_SW        3'b110
`define C_FUNC3_SD        3'b111

// Quadrant C1 Defines
`define C_FUNC3_ADDI      3'b000
`define C_FUNC3_ADDIW     3'b001
`define C_FUNC3_LI        3'b010
`define C_FUNC3_ADDI16SPN 3'b011 // if rd == 2
`define C_FUNC3_LUI       3'b011 // if rd != 2
`define C_FUNC3_MISC_ALU  3'b100
`define C_FUNC3_J         3'b101
`define C_FUNC3_BEQZ      3'b110
`define C_FUNC3_BNEZ      3'b111

// Quadrant C2 Defines
`define C_FUNC3_SLLI      3'b000
`define C_FUNC3_LWSP      3'b010
`define C_FUNC3_LDSP      3'b011
`define C_FUNC3_JR_MV_ADD 3'b100
`define C_FUNC3_SWSP      3'b110
`define C_FUNC3_SDSP      3'b111

// func4 codes
`define C_FUNC4_JR        4'b1000
`define C_FUNC4_MV        4'b1000
`define C_FUNC4_JALR      4'b1001
`define C_FUNC4_ADD       4'b1001
`define C_FUNC4_EBREAK    4'b1001

// func6 codes
`define C_FUNC6_SRLI64    6'b100000
`define C_FUNC6_SRAI64    6'b100001
`define C_FUNC6_ANDI      6'b100010
`define C_FUNC6_SUB       6'b100011
`define C_FUNC6_XOR       6'b100011
`define C_FUNC6_OR        6'b100011
`define C_FUNC6_AND       6'b100011
`define C_FUNC6_SUBW      6'b100111
`define C_FUNC6_ADDW      6'b100111


///////////////////////////////////////////////////////////////////////////////////////////////////
//                                        Zifencei Defines                                       //
///////////////////////////////////////////////////////////////////////////////////////////////////

`define MISC_MEM_FENCE_I         3'b001

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                           ALU Defines                                         //
///////////////////////////////////////////////////////////////////////////////////////////////////

// ALU Codes { func7[5], func7[0], func3, opcode[3] }
`define ALU_OP_ADD          6'b0_0_000_0
`define ALU_OP_SLL          6'b0_0_001_0
`define ALU_OP_SLT          6'b0_0_010_0
`define ALU_OP_SLTU         6'b0_0_011_0
`define ALU_OP_XOR          6'b0_0_100_0
`define ALU_OP_SRL          6'b0_0_101_0
`define ALU_OP_OR           6'b0_0_110_0
`define ALU_OP_AND          6'b0_0_111_0
`define ALU_OP_SUB          6'b1_0_000_0
`define ALU_OP_SRA          6'b1_0_101_0
`define ALU_OP_PASS         6'b1_0_111_0
// RV64I W (32 bit) opcodes
`define ALU_OP_ADDW         6'b0_0_000_1
`define ALU_OP_SLLW         6'b0_0_001_1
`define ALU_OP_SRLW         6'b0_0_101_1
`define ALU_OP_SUBW         6'b1_0_000_1
`define ALU_OP_SRAW         6'b1_0_101_1
// M ALU opcodes
`define ALU_OP_MUL          6'b0_1_000_0
`define ALU_OP_MULH         6'b0_1_001_0
`define ALU_OP_MULHSU       6'b0_1_010_0
`define ALU_OP_MULHU        6'b0_1_011_0
`define ALU_OP_DIV          6'b0_1_100_0
`define ALU_OP_DIVU         6'b0_1_101_0
`define ALU_OP_REM          6'b0_1_110_0
`define ALU_OP_REMU         6'b0_1_111_0
`define ALU_OP_MULW         6'b0_1_000_1
`define ALU_OP_DIVW         6'b0_1_100_1
`define ALU_OP_DIVUW        6'b0_1_101_1
`define ALU_OP_REMW         6'b0_1_110_1
`define ALU_OP_REMUW        6'b0_1_111_1

`define FUNC3_ALU_SHIFT_L   3'b001
`define FUNC3_ALU_SHIFT_R   3'b101

// ALU Operand A
`define ALU_A_SRC_RS1       3'b000
`define ALU_A_SRC_U_IMMED   3'b001
`define ALU_A_SRC_J_IMMED   3'b010
`define ALU_A_SRC_B_IMMED   3'b011
`define ALU_A_SRC_CSR_IMMED 3'b100

// ALU Operand B
`define ALU_B_SRC_RS2       2'b00
`define ALU_B_SRC_I_IMMED   2'b01
`define ALU_B_SRC_S_IMMED   2'b10
`define ALU_B_SRC_PC        2'b11

// Division-Specific Numeric Constants
`define NEGATIVE_1          64'hFFFFFFFFFFFFFFFF
`define NEGATIVE_1_W        32'hFFFFFFFF
`define DIV_MOST_NEG_INT    64'h8000000000000000
`define DIV_MOST_NEG_INT_W  32'h80000000


`endif // LUCID64_VH


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
