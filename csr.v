///////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                               //
// File Name  : csr.v                                                                            //
// Description: The control and status registers and interrupt controller for an RV64I_Zicsr     //
//              hart.                                                                            //
// Author     : Peter Herrmann                                                                   //
//                                                                                               //
// SPDX-License-Identifier: CC-BY-NC-ND-4.0                                                      //
//                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////
`include "csr.vh"
`include "Lucid64.vh"


module csr #(parameter VADDR = 39) (
    input                   clk_i,
    input                   rst_ni,

    input                   wr_en_i,
    input                   rd_en_i,
    input      [11:0]       rd_addr_i,
    input      [11:0]       wr_addr_i,
    input      [`XLEN-1:0]  wdata_i,
    output reg [`XLEN-1:0]  rdata_o,

    input                   unalign_load_ex_i,
    input                   unalign_store_ex_i,
    input                   ecall_ex_i,
    input                   ebreak_ex_i,
    input                   illegal_inst_ex_i,

    input                   m_ext_inter_i,
    input                   m_soft_inter_i,
    input                   m_timer_inter_i,

    input [VADDR-1:0]       EXE_exc_pc_i,
    input [VADDR-1:0]       MEM_exc_pc_i,
    input [VADDR-1:0]       load_store_bad_addr,

    input                   mret_i,
    input                   instr_retired_i,
    input      [`XLEN-1:0]  time_i,

    output wire             csr_interrupt_ao,
    output reg  [VADDR-1:0] csr_branch_addr_o,

    output wire [VADDR-1:0] trap_ret_addr_o
);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                __  __            _     _               ____ ____  ____                    //
    //               |  \/  | __ _  ___| |__ (_)_ __   ___   / ___/ ___||  _ \ ___               //
    //               | |\/| |/ _` |/ __| '_ \| | '_ \ / _ \ | |   \___ \| |_) / __|              //
    //               | |  | | (_| | (__| | | | | | | |  __/ | |___ ___) |  _ <\__ \              //
    //               |_|  |_|\__,_|\___|_| |_|_|_| |_|\___|  \____|____/|_| \_\___/              //
    //                                                                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg [1:0] privilege_mode;
    // Register Write Controls
    reg wr_mstatus,   wr_misa,       wr_mie,        wr_mtvec,     wr_mcountinhibit,  wr_mscratch, 
        wr_mepc,      wr_mcause,     wr_mtval,      wr_mip,       wr_mtval2,         wr_mcycle,
        wr_minstret,  wr_mcounteren;
    // Interrupt Signals
    wire M_inter_en, M_ext_inter, M_timer_inter, M_soft_inter, M_interrupt_a;
    wire M_intr_taken_a, M_exception_a, illegal_inst_ex;
    reg  M_intr_taken_r;   

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                Machine ISA Register (misa)                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg  [25:0] extensions;

    always @(posedge clk_i) begin : misa_logic
        if (~rst_ni)
            extensions <= `MISA_SUPPORTED;
        else if (wr_misa)
            extensions <= wdata_i[25:0];
    end

    wire [`XLEN-1:0] misa_rdata = { `MXLEN, 36'b0, (extensions & `MISA_SUPPORTED) };


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                             Machine Status Register (mstatus)                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    // Machine Status register (mstatus)
    reg       TSR, TW, TVM, MXR, SUM, MPRV, SPP, MPIE, SPIE, MIE, SIE;
    reg [1:0] MPP;

    // Unsupported (Read-only 0) optional feature fields
    wire       MBE = `MSTATUS_LITTLE_ENDIAN;   // Machine byte endianness
    wire       SBE = MBE;                      // Supervisor byte endianness
    wire       UBE = MBE;                      // User byte endianness
    wire [1:0] SXL = `MXLEN;                   // Supervisor Mode XLEN
    wire [1:0] UXL = `MXLEN;                   // User Mode XLEN
    wire [1:0] FS  = 'b0;                      // Floating point unit state
    wire [1:0] VS  = 'b0;                      // Vector unit state
    wire [1:0] XS  = 'b0;                      // User Mode extension state
    wire       SD  = 'b0;                      // Extension state dirty 

    always @(posedge clk_i) begin : mstatus_logic
        if (~rst_ni) begin
            // Machine Mode Fields
            privilege_mode  <= `MACHINE_MODE;
            MPP             <= `MACHINE_MODE;  // Machine Previous Privilege Mode
            MPRV            <= 'b0;            // Modify PRiVilege
            MIE             <= 'b0;            // Machine Interrupt Global Enable
            MPIE            <= 'b0;            // Machine Previous Interrupt Global Enable
            // Supervisor Mode Fields (TODO)
            TW              <= 'b0;            // Timeout Wait
            TSR             <= 'b0;            // Trap SRET
            TVM             <= 'b0;            // Trap Virtual Memory
            MXR             <= 'b0;            // Make eXecutable Readable
            SUM             <= 'b0;            // permit Supervisor User Memory access
            SIE             <= 'b0;            // Supervisor Interrupt Global Enable
            SPP             <= 'b0;            // Supervisor Previous Privilege Mode
            SPIE            <= 'b0;            // Supervisor Previous Interrupt Global Enable
        end else if (wr_mstatus) begin
            MIE             <= wdata_i[3];
            MPIE            <= wdata_i[7];
            MPP             <= wdata_i[12:11];
            MPRV            <= wdata_i[17];
        end else if (mret_i) begin
            privilege_mode  <= MPP;
            MIE             <= MPIE;
            MPIE            <= 'b1;
            MPRV            <= (MPP == `MACHINE_MODE) ? MPRV : 'b0;
            MPP             <= `LOWEST_PRIVILEGE;
        end
    end

    wire [`XLEN-1:0] mstatus_rdata = { SD,   25'b0, MBE,  SBE,  SXL, UXL, 9'b0, TSR, TW,   TVM, 
                                     MXR,  SUM,   MPRV, XS,   FS,  MPP, VS,   SPP, MPIE, UBE, 
                                     SPIE, 1'b0,  MIE,  1'b0, SIE, 1'b0 };


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                     Machine Trap-Vector Base-Address Register (mtvec)                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg  [1:0]  mtvec_mode;
    reg  [VADDR-1:2] mtvec_base;

    always @(posedge clk_i) begin : mtvec_logic
        if (~rst_ni)
            { mtvec_base, mtvec_mode } <= 'b0;
        else if (wr_mtvec)
            { mtvec_base, mtvec_mode } <= wdata_i[VADDR-1:0];
    end

    wire [`XLEN-1:0] mtvec_rdata = { {`XLEN-VADDR{1'b0}}, mtvec_base, mtvec_mode };


     ///////////////////////////////////////////////////////////////////////////////////////////////
    //                               Machine Interrupt Enable (mie)                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg mie_MEIE, mie_MTIE, mie_MSIE;

    always @(posedge clk_i) begin : mie_logic
        if (~rst_ni) begin
            mie_MEIE <= 'b0;
            mie_MTIE <= 'b0;
            mie_MSIE <= 'b0;
        end else if (wr_mie) begin
            mie_MEIE <= wdata_i[11];
            mie_MTIE <= wdata_i[7];
            mie_MSIE <= wdata_i[5];
        end 
    end

    wire [`XLEN-1:0] mie_rdata = {52'b0, mie_MEIE, 3'b0, mie_MTIE, 3'b0, mie_MSIE, 3'b0};


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              Machine Interrupt Pending (mip)                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg mip_MEIP, mip_MTIP, mip_MSIP;

    always @(posedge clk_i) begin : mip_logic
        if (~rst_ni || M_intr_taken_r) begin
            mip_MEIP <= 'b0;
            mip_MTIP <= 'b0;
            mip_MSIP <= 'b0;
        end else if (wr_mip) begin
            mip_MEIP <= wdata_i[11];
            mip_MTIP <= wdata_i[7];
            mip_MSIP <= wdata_i[3];
        end else begin
            mip_MEIP <= mie_MEIE | m_ext_inter_i;
            mip_MTIP <= mie_MTIE | m_timer_inter_i;
            mip_MSIP <= mie_MSIE | m_soft_inter_i;
        end
    end

    wire [`XLEN-1:0] mip_rdata = {52'b0, mip_MEIP, 3'b0, mip_MTIP, 3'b0, mip_MSIP, 3'b0};


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                         Machine Counter-Inhibit CSR (mcountinhibit)                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg [31:0] mcountinhibit;

    always @(posedge clk_i) begin : mcountinhibit_logic
        if (~rst_ni)
            mcountinhibit <= 'b0;
        else if (wr_mcountinhibit)
            mcountinhibit <= wdata_i[31:0];
    end

    wire mcycle_inhibited   = mcountinhibit[0];
    wire minstret_inhibited = mcountinhibit[2];

    wire [`XLEN-1:0] mcountinhibit_rdata = { 32'b0, mcountinhibit };


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                           Machine Counter-Enable CSR (mcounteren)                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg [31:0] mcounteren;

    always @(posedge clk_i) begin : mcounteren_logic
        if (~rst_ni)
            mcounteren <= 'b0;
        else if (wr_mcounteren)
            mcounteren <= wdata_i[31:0];
    end

    wire cycle_enabled   = mcounteren[0];
    wire time_enabled    = mcounteren[1];
    wire instret_enabled = mcounteren[2];

    wire [`XLEN-1:0] mcounteren_rdata = { 32'b0, mcounteren };


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                            Machine Scratch Register (mscratch)                            //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg [`XLEN-1:0] mscratch;
    
    always @(posedge clk_i) begin : mscratch_logic
        if (~rst_ni)
            mscratch <= 'b0;
        else if (wr_mscratch)
            mscratch <= wdata_i;
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                         Machine Exception Program Counter (mepc)                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg [`XLEN-1:1] mepc;

    wire [`XLEN-1:1] MEM_pc = { {`XLEN-VADDR{1'b0}}, MEM_exc_pc_i[VADDR-1:1]};
    wire [`XLEN-1:0] EXE_pc = { {`XLEN-VADDR{1'b0}}, EXE_exc_pc_i[VADDR-1:0]};

    always @(posedge clk_i) begin : mepc_logic
        if (~rst_ni)
            mepc <= 'b0;
        else if (wr_mepc)
            mepc <= wdata_i[`XLEN-1:1];
        else if (unalign_store_ex_i || unalign_load_ex_i)
            mepc <= MEM_pc[`XLEN-1:1];
        else if (M_intr_taken_a)
            mepc <= EXE_pc[`XLEN-1:1];
    end

    wire [`XLEN-1:0] mepc_rdata = { mepc, 1'b0 };
    
    wire _unused = MEM_exc_pc_i[0];


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              Machine Cause Register (mcause)                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg mcause_int;
    reg [62:0] mcause_code;

    always @(posedge clk_i) begin : mcause_logic
        if (~rst_ni)
            mcause_code <= 'b0;
        else if (ebreak_ex_i)
            mcause_code  <= `MCAUSE_BREAKPOINT;
        else if (ecall_ex_i)
            mcause_code  <= `MCAUSE_ECALL_FROM_M_MODE;
        else if (illegal_inst_ex)
            mcause_code  <= `MCAUSE_ILLEGAL_INST;
        else if (unalign_load_ex_i)
            mcause_code  <= `MCAUSE_LOAD_ADDR_MISALIGNED;
        else if (unalign_store_ex_i)
            mcause_code  <= `MCAUSE_STORE_AMO_MISALIGNED;
        else if (M_timer_inter)
            mcause_code  <= `MCAUSE_MACH_TIMER_INT;
        else if (M_ext_inter)
            mcause_code  <= `MCAUSE_MACH_EXT_INT;
        else if (M_soft_inter)
            mcause_code  <= `MCAUSE_MACH_SOFT_INT;
        else if (wr_mcause)
            mcause_code <= wdata_i[62:0];

        if (~rst_ni || M_exception_a)
            mcause_int <= 'b0;
        else if (M_interrupt_a)
            mcause_int <= 'b1;
        else if (wr_mcause)
            mcause_int <= wdata_i[`XLEN-1];
    end

    wire [`XLEN-1:0] mcause_rdata = { mcause_int, mcause_code };


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 Machine Trap Value (mtval)                                //    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg  [`XLEN-1:0] mtval;
    wire [`XLEN-1:0] LS_bad_addr = { {`XLEN-VADDR{1'b0}}, load_store_bad_addr[VADDR-1:0]};

    always @(posedge clk_i) begin : mtval_logic
        if (~rst_ni)
            mtval <= 'b0;
        else if ( ebreak_ex_i )
            mtval <= EXE_pc;
        else if ( unalign_load_ex_i || unalign_store_ex_i )
            mtval <= LS_bad_addr;
        else if ( wr_mtval )
            mtval <= wdata_i;
        else if ( M_exception_a && ~ecall_ex_i )
            mtval <= 'b0;
        // TODO: implement mtval behavior on all exceptions.
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                               Machine Trap Value 2 (mtval2)                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg [`XLEN-1:0] mtval2;
    
    always @(posedge clk_i) begin : mtval2_logic
        if (~rst_ni)
            mtval2 <= 'b0;
        else if (wr_mtval2)
            mtval2 <= wdata_i;
        // TODO
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //      __  __  _   _  ____   __  __      ____                      _                        //
    //     |  \/  || | | ||  _ \ |  \/  |    / ___| ___   _   _  _ __  | |_  ___  _ __  ___      //
    //     | |\/| || |_| || |_) || |\/| |   | |    / _ \ | | | || '_ \ | __|/ _ \| '__|/ __|     //
    //     | |  | ||  _  ||  __/ | |  | |   | |___| (_) || |_| || | | || |_|  __/| |   \__ \     //
    //     |_|  |_||_| |_||_|    |_|  |_|    \____|\___/  \__,_||_| |_| \__|\___||_|   |___/     //
    //                                                                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                Machine Cycle Counter (mcycle)                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg [`XLEN-1:0] mcycle;

    always @(posedge clk_i) begin : mcycle_logic
        if (~rst_ni)
            mcycle <= 'b0;
        else if (wr_mcycle)
            mcycle <= wdata_i;
        else if (~mcycle_inhibited)
            mcycle <= mcycle + 1;
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                        Machine Instruction Retired Counter (minstret)                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    reg [`XLEN-1:0] minstret;

    always @(posedge clk_i) begin : minstret_logic
        if (~rst_ni)
            minstret <= 'b0;
        else if (wr_minstret)
            minstret <= wdata_i;
        else if (instr_retired_i && ~minstret_inhibited)
            minstret <= minstret + 1;
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //              Unnamed Machine Hardware Performance Counters (mhpmcounter 3 - 31)           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // TODO
    
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //         ____                              _                   ____ ____  ____             //
    //        / ___| _   _ _ __   ___ _ ____   _(_)___  ___  _ __   / ___/ ___||  _ \ ___        //
    //        \___ \| | | | '_ \ / _ \ '__\ \ / / / __|/ _ \| '__| | |   \___ \| |_) / __|       //
    //         ___) | |_| | |_) |  __/ |   \ V /| \__ \ (_) | |    | |___ ___) |  _ <\__ \       //
    //        |____/ \__,_| .__/ \___|_|    \_/ |_|___/\___/|_|     \____|____/|_| \_\___/       //
    //                    |_|                                                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //               ____                _    ____            _             _                    //
    //              |  _ \ ___  __ _  __| |  / ___|___  _ __ | |_ _ __ ___ | |___                //
    //              | |_) / _ \/ _` |/ _` | | |   / _ \| '_ \| __| '__/ _ \| / __|               //
    //              |  _ <  __/ (_| | (_| | | |__| (_) | | | | |_| | | (_) | \__ \               //
    //              |_| \_\___|\__,_|\__,_|  \____\___/|_| |_|\__|_|  \___/|_|___/               //
    //                                                                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg illegal_m_rd, illegal_sv_rd, illegal_hv_rd, illegal_u_rd, illegal_csr_rd;
    
    always @(posedge clk_i) begin
        if (~rst_ni) begin
            illegal_csr_rd <= 'b0;
            rdata_o        <= 'b0;
            illegal_m_rd   <= 'b0;
            illegal_sv_rd  <= 'b0;
            illegal_u_rd   <= 'b0;
        end else begin
            illegal_m_rd   <= 'b0;
            illegal_sv_rd  <= 'b0;
            illegal_u_rd   <= 'b0;

            if (rd_en_i) begin
                case (rd_addr_i[9:8]) // CSR privilege Modes

                    `MACHINE_MODE: begin
                        if (privilege_mode != `MACHINE_MODE) begin
                            rdata_o                      <= {52'b0, rd_addr_i};
                            illegal_m_rd                 <= 'b1;
                        end else case (rd_addr_i)
                            // Machine Information Registers (Machine Read-Only)
                            `CSR_MVENDORID     : rdata_o <= `VENDOR_ID_VAL;
                            `CSR_MARCHID       : rdata_o <= `MARCH_ID_VAL;
                            `CSR_MIMPID        : rdata_o <= `IMP_ID_VAL;
                            `CSR_MHARTID       : rdata_o <= `HART_ID_VAL;
                            `CSR_MCONFIGPTR    : rdata_o <= `CONFIG_PTR_VAL;
                            // Machine Trap Setup (Machine Read-Write)
                            `CSR_MSTATUS       : rdata_o <= mstatus_rdata;
                            `CSR_MISA          : rdata_o <= misa_rdata;
                            `CSR_MIE           : rdata_o <= mie_rdata;
                            `CSR_MTVEC         : rdata_o <= mtvec_rdata;
                            // Machine Counter Setup (Machine Read-Write)
                            `CSR_MCOUNTEREN    : rdata_o <= mcounteren_rdata;
                            `CSR_MCOUNTINHIBIT : rdata_o <= mcountinhibit_rdata;
                            // Machine Trap Handline (Machine Read-Write)
                            `CSR_MSCRATCH      : rdata_o <= mscratch;
                            `CSR_MEPC          : rdata_o <= mepc_rdata;
                            `CSR_MCAUSE        : rdata_o <= mcause_rdata;
                            `CSR_MTVAL         : rdata_o <= mtval;
                            `CSR_MIP           : rdata_o <= mip_rdata;
                            `CSR_MTVAL2        : rdata_o <= mtval2;
                            // MHPM Counters
                            `CSR_MCYCLE        : rdata_o <= mcycle;
                            `CSR_MINSTRET      : rdata_o <= minstret;

                            default: begin
                                rdata_o                  <= {52'b0, rd_addr_i};
                                illegal_m_rd             <= 'b1;
                            end
                        endcase
                    end // Machine Mode


                    `SUPERVISOR_MODE: begin
                        if (privilege_mode == `USER_MODE) begin
                            rdata_o                      <= {52'b0, rd_addr_i};
                            illegal_sv_rd                <= 'b1;
                        end else case (rd_addr_i)

                            default: begin
                                rdata_o                  <= {52'b0, rd_addr_i};
                                illegal_sv_rd            <= 'b1;
                            end
                        
                        endcase
                    end // Supervisor Mode


                    `USER_MODE: begin
                        case (rd_addr_i)
                            `CSR_CYCLE: begin
                                illegal_u_rd <= ~cycle_enabled;
                                rdata_o      <= cycle_enabled ? mcycle : 'b0;
                            end

                            `CSR_TIME: begin
                                illegal_u_rd <= ~time_enabled;
                                rdata_o      <= time_enabled ? time_i : 'b0;
                            end

                            `CSR_INSTRET: begin
                                illegal_u_rd <= ~instret_enabled;
                                rdata_o      <= instret_enabled ? minstret : 'b0;
                            end

                            default: begin
                                rdata_o                  <= {52'b0, rd_addr_i};
                                illegal_u_rd             <= 'b1;
                            end
                        endcase
                    end // User Mode


                    default: begin
                        rdata_o       <= {52'b0, rd_addr_i};
                        illegal_hv_rd <= 'b1;
                    end

                endcase // case (rd_addr_i[9:8])
            end // rd_en_i

            illegal_csr_rd <= illegal_m_rd || illegal_sv_rd || illegal_u_rd || illegal_hv_rd;
        end
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //       __        __      _  _           ____               _                _              //
    //       \ \      / /_ __ (_)| |_  ___   / ___| ___   _ __  | |_  _ __  ___  | | ___         //
    //        \ \ /\ / /| '__|| || __|/ _ \ | |    / _ \ | '_ \ | __|| '__|/ _ \ | |/ __|        //
    //         \ V  V / | |   | || |_|  __/ | |___| (_) || | | || |_ | |  | (_) || |\__ \        //
    //          \_/\_/  |_|   |_| \__|\___|  \____|\___/ |_| |_| \__||_|   \___/ |_||___/        //
    //                                                                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    reg illegal_m_wr, illegal_sv_wr, illegal_hv_wr, illegal_u_wr, illegal_csr_wr;
    
    always @(*) begin
        if (~rst_ni) begin
            { illegal_m_wr, illegal_sv_wr, illegal_u_wr, wr_mstatus, wr_misa, wr_mie, wr_mtvec, 
              wr_mcountinhibit, wr_mscratch, wr_mepc, wr_mcause, wr_mtval, wr_mip, wr_mtval2, 
              wr_mcycle, wr_minstret, illegal_csr_wr, wr_mcounteren, illegal_hv_wr } = 'b0;
        end else begin
            { illegal_m_wr, illegal_sv_wr, illegal_u_wr, wr_mstatus, wr_misa, wr_mie, wr_mtvec, 
              wr_mcountinhibit, wr_mscratch, wr_mepc, wr_mcause, wr_mtval, wr_mip, wr_mtval2, 
              wr_mcycle, wr_minstret, wr_mcounteren, illegal_hv_wr } = 'b0;

            if (wr_en_i) begin
                case (wr_addr_i[9:8]) // CSR privilege Modes

                    `MACHINE_MODE: begin
                        if (privilege_mode != `MACHINE_MODE) 
                            illegal_m_wr                            = 1'b1;
                        else case (wr_addr_i)
                            // Machine Trap Setup (Machine Read-Write)
                            `CSR_MSTATUS       : wr_mstatus         = 1'b1;
                            `CSR_MISA          : wr_misa            = 1'b1;
                            `CSR_MIE           : wr_mie             = 1'b1;
                            `CSR_MTVEC         : wr_mtvec           = 1'b1;
                            // Machine Counter Setup (Machine Read-Write)
                            `CSR_MCOUNTEREN    : wr_mcounteren      = 1'b1;
                            `CSR_MCOUNTINHIBIT : wr_mcountinhibit   = 1'b1;
                            // Machine Trap Handline (Machine Read-Write)
                            `CSR_MSCRATCH      : wr_mscratch        = 1'b1;
                            `CSR_MEPC          : wr_mepc            = 1'b1;
                            `CSR_MCAUSE        : wr_mcause          = 1'b1;
                            `CSR_MTVAL         : wr_mtval           = 1'b1;
                            `CSR_MIP           : wr_mip             = 1'b1;
                            `CSR_MTVAL2        : wr_mtval2          = 1'b1;
                            // MHPM Counters
                            `CSR_MCYCLE        : wr_mcycle          = 1'b1;
                            `CSR_MINSTRET      : wr_minstret        = 1'b1;

                            default            : illegal_m_wr       = 1'b1;
                        endcase
                    end // Machine Mode


                    `SUPERVISOR_MODE: begin
                        if (privilege_mode == `USER_MODE)
                            illegal_sv_wr          = 'b1;
                        else case (wr_addr_i)
                            default: illegal_sv_wr = 'b1;
                        endcase
                    end // Supervisor


                    `USER_MODE: begin
                        case (wr_addr_i)
                            default: illegal_u_wr = 'b1;
                        endcase
                    end // Supervisor


                    default: illegal_hv_wr = 'b1;

                endcase // case (wr_addr_i[9:8])
            end // wr_en_i

            illegal_csr_wr = illegal_m_wr || illegal_sv_wr || illegal_u_wr || illegal_hv_wr;
        end
    end


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                  ___         _                                   _                        //
    //                 |_ _| _ __  | |_  ___  _ __  _ __  _   _  _ __  | |_  ___                 //
    //                  | | | '_ \ | __|/ _ \| '__|| '__|| | | || '_ \ | __|/ __|                //
    //                  | | | | | || |_|  __/| |   | |   | |_| || |_) || |_ \__ \                //
    //                 |___||_| |_| \__|\___||_|   |_|    \__,_|| .__/  \__||___/                //
    //                                                          |_|                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    wire [VADDR-1:0] vectored_offset = mcause_code[VADDR+1:2];
    wire [VADDR-1:0] direct_target   = { mtvec_base, 2'b0 };

    always @(posedge clk_i) begin
        M_intr_taken_r <= rst_ni ? M_intr_taken_a : 'b0;
    end

    always @(*) begin
        if (mtvec_mode == `MTVEC_MODE_VECTORED && ~M_exception_a) 
            csr_branch_addr_o  = direct_target + vectored_offset;
        else begin
            csr_branch_addr_o  = direct_target;
        end
    end

    // Interrupt masking
    assign M_inter_en    = MIE || (privilege_mode != `MACHINE_MODE);
    assign M_ext_inter   = mip_MEIP && mie_MEIE && M_inter_en;
    assign M_timer_inter = mip_MTIP && mie_MTIE && M_inter_en;
    assign M_soft_inter  = mip_MSIP && mie_MSIE && M_inter_en;
    assign M_interrupt_a = M_ext_inter || M_timer_inter || M_soft_inter;

    assign illegal_inst_ex = illegal_inst_ex_i || illegal_csr_rd || illegal_csr_wr;

    assign M_exception_a = (unalign_load_ex_i  || illegal_inst_ex || ecall_ex_i || 
                          unalign_store_ex_i || ebreak_ex_i );

    assign M_intr_taken_a = M_exception_a || M_interrupt_a;

    assign csr_interrupt_ao = M_intr_taken_a;

    assign trap_ret_addr_o = mepc_rdata[VADDR-1:0];


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
