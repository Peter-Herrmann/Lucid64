///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// File Name  : csr.vh                                                                           //
// Description: This header contains definitions used for the Control and Status Register (CSR)s //
//              implemented here. The CSRs defined are in compliance with the RISC-V Machine ISA //
//              v1.12, and further documentation can be found in the The RISC-V Instruction Set  //
//              Manual Volume II: Privileged Architecture                                        //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: Apache-2.0                                                           //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`ifndef CSR_VH
`define CSR_VH



///////////////////////////////////////////////////////////////////////////////////////////////////
//                                       Privilege Modes                                      //
///////////////////////////////////////////////////////////////////////////////////////////////////

`define USER_MODE           2'b00
`define SUPERVISOR_MODE     2'b10
`define MACHINE_MODE        2'b11

`define LOWEST_PRIVILEGE    `MACHINE_MODE


///////////////////////////////////////////////////////////////////////////////////////////////////
//       __  __            _     _              __  __          _         ___  ___  ___          //
//      |  \/  | __ _  __ | |_  (_) _ _   ___  |  \/  | ___  __| | ___   / __|/ __|| _ \ ___     //
//      | |\/| |/ _` |/ _|| ' \ | || ' \ / -_) | |\/| |/ _ \/ _` |/ -_) | (__ \__ \|   /(_-<     //
//      |_|  |_|\__,_|\__||_||_||_||_||_|\___| |_|  |_|\___/\__,_|\___|  \___||___/|_|_\/__/     //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                       Register Addresses                                      //
///////////////////////////////////////////////////////////////////////////////////////////////////

// Machine Information Registers (Machine Read-Only)
`define CSR_MVENDORID       12'hF11     // Vendor ID
`define CSR_MARCHID         12'hF12     // Architecture ID
`define CSR_MIMPID          12'hF13     // Implementation ID
`define CSR_MHARTID         12'hF14     // Hardware thread ID
`define CSR_MCONFIGPTR      12'hF15     // Pointer to configuration data structure
// Machine Trap Setup (Machine Read-Write)
`define CSR_MSTATUS         12'h300     // Machine status
`define CSR_MISA            12'h301     // ISA and extensions
`define CSR_MEDELEG         12'h302     // Machine exception delegation (S extension only)
`define CSR_MIDELEG         12'h303     // Machine interrupt delegation (S extension only)
`define CSR_MIE             12'h304     // Machine interrupt-enable
`define CSR_MTVEC           12'h305     // Machine trap-handler base address
`define CSR_MCOUNTEREN      12'h306     // Machine counter enable
// Machine Counter Setup (Machine Read-Write)
`define CSR_MCOUNTINHIBIT   12'h320     // Machine counter inhibit
`define CSR_MHPMEVENT_3     12'h323     // Machine performance monitoring event selector 3
                                        // (CSR_MHPMEVENT_3) <-> (CSR_MHPMEVENT_3 + 28)
// Machine Trap Handling (Machine Read-Write)
`define CSR_MSCRATCH        12'h340     // Scratch register for machine trap handlers
`define CSR_MEPC            12'h341     // Machine exception program counter
`define CSR_MCAUSE          12'h342     // Machine trap cause
`define CSR_MTVAL           12'h343     // Machine bad address or instruction
`define CSR_MIP             12'h344     // Machine interrupt pending
`define CSR_MTINST          12'h34A     // Machine trap instruction (transformed)
`define CSR_MTVAL2          12'h34B     // Machine bad guest physical address
// Machine Configuration (Machine Read-Write)
`define CSR_MENVCFG         12'h30A     // Machine environment configuration
`define CSR_MSECCFG         12'h747     // Machine security configuration
// Machine Memory Protection (Machine Read-Write)
`define CSR_PMPCFG_BASE     12'h3A0     // Physical memory protection configuration
                                        // (CSR_PMPCFG_BASE) <-> (CSR_PMPCFG_BASE + 15)
                                        // Odd numbered registers only in RV32
`define CSR_PMPADDR_BASE    12'h3B0     // Physical memory protection address
                                        // (CSR_PMPADDR_BASE) <-> (CSR_PMPADDR_BASE + 63)
// Machine Hardware Performance Counters
`define CSR_MCYCLE          12'hB00     // Machine Cycle Counter (mhpmcounter 0 and 1)
`define CSR_MINSTRET        12'hB02     // Machine Instruction Retired Counter (mhpmcounter 2)

`define NUM_CSR_MHPM_COUNTERS 32

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                 Machine Information Registers                                 //
///////////////////////////////////////////////////////////////////////////////////////////////////

`define VENDOR_ID_VAL       'b0
`define MARCH_ID_VAL        'b0
`define IMP_ID_VAL          'b0
`define HART_ID_VAL         'b0
`define CONFIG_PTR_VAL      'b0


///////////////////////////////////////////////////////////////////////////////////////////////////
//                                      Machine Trap Setup                                       //
///////////////////////////////////////////////////////////////////////////////////////////////////

// Machine Status register (mstatus)


// Machine ISA Register (misa)
// HW supported ISA extensions: ZY_XWVU_TSRQ_PONM_LKJI_HGFE_DCBA
`define MISA_SUPPORTED      26'b00_0000_0000_0001_0001_0000_0101 // IMAC
`define MXLEN               2'd2                                 // XLEN = 64

`define MTVEC_MODE_DIRECT   2'b0
`define MTVEC_MODE_VECTORED 2'b1

`define MCAUSE_SUPERV_SOFT_INT          63'd1
`define MCAUSE_MACH_SOFT_INT            63'd3
`define MCAUSE_SUPERV_TIMER_INT         63'd5
`define MCAUSE_MACH_TIMER_INT           63'd7
`define MCAUSE_SUPERV_EXT_INT           63'd9
`define MCAUSE_MACH_EXT_INT             63'd11

`define MCAUSE_INST_ADDR_MISALIGNED     63'd0
`define MCAUSE_INST_ACCESS_FAULT        63'd1
`define MCAUSE_ILLEGAL_INST             63'd2
`define MCAUSE_BREAKPOINT               63'd3
`define MCAUSE_LOAD_ADDR_MISALIGNED     63'd4
`define MCAUSE_LOAD_ACCESS_FAULT        63'd5
`define MCAUSE_STORE_AMO_MISALIGNED     63'd6
`define MCAUSE_STORE_AMO_ACCESS_FAULT   63'd7
`define MCAUSE_ECALL_FROM_U_MODE        63'd8
`define MCAUSE_ECALL_FROM_S_MODE        63'd9
`define MCAUSE_ECALL_FROM_M_MODE        63'd11
`define MCAUSE_INST_PAGE_FAULT          63'd12
`define MCAUSE_LOAD_PAGE_FAULT          63'd13
`define MCAUSE_STORE_AMO_PAGE_FAULT     63'd15

`define MSTATUS_LITTLE_ENDIAN           1'b0
`define MSTATUS_BIG_ENDIAN              1'b1


///////////////////////////////////////////////////////////////////////////////////////////////////
//               _   _                  __  __          _         ___  ___  ___                  //
//              | | | | ___  ___  _ _  |  \/  | ___  __| | ___   / __|/ __|| _ \ ___             //
//              | |_| |(_-< / -_)| '_| | |\/| |/ _ \/ _` |/ -_) | (__ \__ \|   /(_-<             //
//               \___/ /__/ \___||_|   |_|  |_|\___/\__,_|\___|  \___||___/|_|_\/__/             //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////

`define CSR_CYCLE       12'hC00
`define CSR_TIME        12'hC01
`define CSR_INSTRET     12'hC02


`endif // CSR_VH


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
