// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
package ppc_pkg;
  // Unit and standalone MMU builds import this package without every consumer.
  /* verilator lint_off UNUSEDPARAM */
  localparam int IQ_DEPTH = 6;
  localparam int GPR_RENAME_DEPTH = 5;
  localparam int CQ_DEPTH = 5;
  localparam int TAG_WIDTH = $clog2(GPR_RENAME_DEPTH);
  typedef logic [TAG_WIDTH-1:0] rename_tag_t;
  localparam int CQ_INDEX_WIDTH = $clog2(CQ_DEPTH);
  localparam int CQ_GENERATION_WIDTH = 8;
  typedef struct packed {
    logic [CQ_INDEX_WIDTH-1:0] index;
    logic [CQ_GENERATION_WIDTH-1:0] generation;
  } completion_tag_t;
  typedef struct packed {
    logic ready;
    logic [31:0] value;
    rename_tag_t tag;
    completion_tag_t producer;
  } operand_t;
  // Synchronous data faults. DATA_MACHINE_CHECK is a bus TEA returned for
  // machine-check entry; other transport errors remain separate.
  typedef enum logic [2:0] {
    DATA_OK = 3'd0,
    DATA_DSI_PROTECTION = 3'd1,
    DATA_PAGE_MISS = 3'd2,
    DATA_PAGE_CHANGED = 3'd3,
    DATA_DSI_DIRECT_STORE = 3'd4,
    DATA_MACHINE_CHECK = 3'd5,
    // eciwx/ecowx with EAR[E] = 0.
    DATA_DSI_EXTERNAL = 3'd6
  } data_fault_t;
  // Response-bound context for a diagnostic page miss or changed-bit store.
  // The router captures these fields with the accepted translation request.
  typedef struct packed {
    logic [31:0] ea;
    logic [31:0] sr;
    logic pr;
    logic ir;
    logic dr;
    logic write;
    logic way;
  } page_miss_t;
  typedef struct packed {
    completion_tag_t producer;
    logic [31:0] value;
    logic [31:0] update_value;
    logic fault;
    data_fault_t data_fault;
    page_miss_t page_miss;
    logic ca;
    logic ov;
    logic so;
    logic [3:0] cr0;
  } result_packet_t;
  typedef struct packed {
    completion_tag_t producer;
    rename_tag_t tag;
    logic [31:0] value;
  } wake_packet_t;
  // Fetch-borne events. FETCH_MACHINE_CHECK is a bus TEA on the fetch;
  // FETCH_IABR marks an instruction address breakpoint match at IQ push.
  typedef enum logic [2:0] {
    FETCH_OK = 3'd0,
    FETCH_ISI_PROTECTION = 3'd1,
    FETCH_ISI_GUARDED = 3'd2,
    FETCH_PAGE_MISS = 3'd3,
    FETCH_MACHINE_CHECK = 3'd4,
    FETCH_IABR = 3'd5
  } fetch_fault_t;
  // The core holds the page-miss context beside the IQ, not per entry.
  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] insn;
    fetch_fault_t fault;
  } fetch_packet_t;

  // MMU request kinds
  // Unlisted codes return unsupported.
  typedef enum logic [2:0] {
    BAT_TRANSLATE_I = 3'd0,
    BAT_TRANSLATE_READ = 3'd1,
    BAT_TRANSLATE_WRITE = 3'd2,
    BAT_SPR_READ = 3'd3,
    BAT_SPR_WRITE = 3'd4,
    BAT_PREPARE_WRITE = 3'd5
  } bat_req_kind_t;
  typedef enum logic [2:0] {
    TLB_LOOKUP = 3'd0,
    TLB_REFILL = 3'd1,
    TLB_INVALIDATE_SET = 3'd2,
    TLB_RESERVED = 3'd3,
    TLB_PREPARE_INVALIDATE = 3'd4,
    TLB_PREPARE_REFILL = 3'd5
  } tlb_req_kind_t;
  typedef enum logic [2:0] {
    SEG_READ = 3'd0,
    SEG_WRITE = 3'd1,
    SEG_SNAPSHOT = 3'd2,
    SEG_PREPARE = 3'd4
  } seg_req_kind_t;
  // End MMU request kinds
  // ALU_ADD computes (invert_a ? ~a : a) + b + carry_in for every add and
  // subtract form. ALU_CMP/ALU_CMPL read signed/unsigned CR bits from the
  // same b - a sum.
  typedef enum logic [4:0] {
    ALU_ADD, ALU_OR, ALU_XOR, ALU_AND, ALU_ANDC,
    ALU_ORC, ALU_NAND, ALU_NOR, ALU_EQV,
    ALU_ROTATE, ALU_SLW, ALU_SRW, ALU_SRAW, ALU_RLWIMI,
    ALU_CNTLZW, ALU_EXTSB, ALU_EXTSH, ALU_MULLW,
    ALU_MULHW, ALU_MULHWU, ALU_DIVWU, ALU_DIVW, ALU_MULLI,
    ALU_CMP, ALU_CMPL
  } alu_op_t;
  typedef enum logic [1:0] {
    CARRY_ZERO, CARRY_ONE, CARRY_CA
  } carry_in_t;
  typedef enum logic [5:0] {
    SPECIAL_NONE, SPECIAL_B, SPECIAL_BC, SPECIAL_BCLR, SPECIAL_BCCTR,
    SPECIAL_MFSPR, SPECIAL_MTSPR,
    SPECIAL_LOAD, SPECIAL_STORE, SPECIAL_MFCR, SPECIAL_MTCRF,
    SPECIAL_CR_LOGIC, SPECIAL_MCRF, SPECIAL_MCRXR,
    SPECIAL_SC, SPECIAL_RFI, SPECIAL_PROGRAM_ILLEGAL,
    SPECIAL_PROGRAM_PRIV, SPECIAL_MFMSR,
    SPECIAL_ISYNC, SPECIAL_SYNC, SPECIAL_EIEIO, SPECIAL_ALIGNMENT, SPECIAL_ISI, SPECIAL_MTMSR,
    SPECIAL_MFSR, SPECIAL_MTSR, SPECIAL_TLBIE,
    SPECIAL_TLBLD, SPECIAL_TLBLI, SPECIAL_TLBSYNC, SPECIAL_ICBI,
    // tw/twi; branch_bo carries TO.
    SPECIAL_TRAP,
    // Floating-point class. Dispatch turns it into SPECIAL_FP_UNAVAILABLE
    // while MSR[FP] = 0 or no FPU is present.
    SPECIAL_FPU, SPECIAL_FP_UNAVAILABLE,
    // 602 (602UM 2.3.4.3.6, 2.3.7, 4.5.18): the emulation trap; a
    // double-precision FP form, which becomes FP unavailable while MSR[FP] = 0
    // and the emulation trap otherwise; esa, dsa and mfrom.
    SPECIAL_EMULATION_TRAP, SPECIAL_FPU_EMULATE,
    SPECIAL_ESA, SPECIAL_DSA, SPECIAL_MFROM
  } special_op_t;
  // 60x transfer class of a data request (UM Table 7-1).
  // DMEM_CACHE is a data-cache operation (cache_op_t in rid); it reaches only
  // a data cache, never the bus.
  typedef enum logic [1:0] {
    DMEM_NORMAL, DMEM_ATOMIC, DMEM_EXTERNAL, DMEM_CACHE
  } dmem_kind_t;
  typedef struct packed {
    dmem_kind_t kind;
    // eciwx/ecowx resource ID, EAR[28:31]: TBST || TSIZ[0:2].
    logic [3:0] rid;
  } dmem_attr_t;
  typedef enum logic [2:0] {
    CACHE_OP_NONE, CACHE_OP_DCBF, CACHE_OP_DCBST, CACHE_OP_DCBI,
    CACHE_OP_DCBZ, CACHE_OP_DCBT, CACHE_OP_DCBTST, CACHE_OP_SYNC
  } cache_op_t;
  typedef enum logic [2:0] {
    CR_LOGIC_AND, CR_LOGIC_ANDC, CR_LOGIC_EQV, CR_LOGIC_NAND,
    CR_LOGIC_NOR, CR_LOGIC_OR, CR_LOGIC_ORC, CR_LOGIC_XOR
  } cr_logic_op_t;
  typedef enum logic [1:0] {
    MEM_BYTE, MEM_HALF, MEM_WORD
  } mem_size_t;
  // Multiple/string byte-count source; dispatch cracks these into one
  // micro-op per register.
  typedef enum logic [1:0] {
    SEQ_NONE, SEQ_MULTIPLE, SEQ_STRING_IMM, SEQ_STRING_INDEXED
  } mem_seq_t;
  // SPR numbers
  // Selector = {insn[15:11], insn[20:16]}. Bit 4 (instruction field bit 0)
  // marks a supervisor-only SPR.
  localparam int SPR_PRIV_BIT = 4;
  localparam logic [9:0] SPR_XER = 10'd1;
  localparam logic [9:0] SPR_LR = 10'd8;
  localparam logic [9:0] SPR_CTR = 10'd9;
  localparam logic [9:0] SPR_DSISR = 10'd18;
  localparam logic [9:0] SPR_DAR = 10'd19;
  localparam logic [9:0] SPR_DEC = 10'd22;
  localparam logic [9:0] SPR_SDR1 = 10'd25;
  localparam logic [9:0] SPR_SRR0 = 10'd26;
  localparam logic [9:0] SPR_SRR1 = 10'd27;
  localparam logic [9:0] SPR_EAR = 10'd282;
  localparam logic [9:0] SPR_PVR = 10'd287;
  localparam logic [9:0] SPR_TBL_READ = 10'd268;
  localparam logic [9:0] SPR_TBU_READ = 10'd269;
  localparam logic [9:0] SPR_SPRG0 = 10'd272;
  localparam logic [9:0] SPR_SPRG3 = 10'd275;
  localparam logic [9:0] SPR_TBL_WRITE = 10'd284;
  localparam logic [9:0] SPR_TBU_WRITE = 10'd285;
  localparam logic [9:0] SPR_IBAT0U = 10'd528;
  localparam logic [9:0] SPR_DBAT3L = 10'd543;
  localparam logic [9:0] SPR_DMISS = 10'd976;
  localparam logic [9:0] SPR_DCMP = 10'd977;
  localparam logic [9:0] SPR_HASH1 = 10'd978;
  localparam logic [9:0] SPR_HASH2 = 10'd979;
  localparam logic [9:0] SPR_IMISS = 10'd980;
  localparam logic [9:0] SPR_ICMP = 10'd981;
  localparam logic [9:0] SPR_RPA = 10'd982;
  localparam logic [9:0] SPR_HID0 = 10'd1008;
  localparam logic [9:0] SPR_HID1 = 10'd1009;
  localparam logic [9:0] SPR_IABR = 10'd1010;
  // 602 only (602UM Table 2-6; SP is 1021, see 2.1.2.4.1).
  localparam logic [9:0] SPR_TCR = 10'd984;
  localparam logic [9:0] SPR_IBR = 10'd986;
  localparam logic [9:0] SPR_ESASRR = 10'd987;
  localparam logic [9:0] SPR_SEBR = 10'd990;
  localparam logic [9:0] SPR_SER = 10'd991;
  localparam logic [9:0] SPR_SP = 10'd1021;
  localparam logic [9:0] SPR_LT = 10'd1022;
  // XER
  localparam int XER_SO_BIT = 31;
  localparam int XER_CA_BIT = 29;
  localparam int XER_BYTE_COUNT_WIDTH = 7;
  localparam logic [31:0] XER_IMPLEMENTED_MASK = 32'he000_007f;
  // IU controls fixed at dispatch; the station holds them unchanged until issue.
  typedef struct packed {
    alu_op_t op;
    logic invert_a;
    carry_in_t carry_in;
    logic [31:0] mask;
    logic [4:0] shift;
    logic ca_in;
    logic so_in;
    logic write_ca;
    logic write_ov_so;
    logic write_cr_field;
    completion_tag_t producer;
  } iu_ctrl_t;
  typedef struct packed {
    iu_ctrl_t ctrl;
    operand_t a;
    operand_t b;
  } rs_entry_t;
  typedef struct packed {
    iu_ctrl_t ctrl;
    logic [31:0] a;
    logic [31:0] b;
  } issue_packet_t;
  typedef struct packed {
    alu_op_t op;
    logic invert_a;
    carry_in_t carry_in;
    logic illegal;
    logic [4:0] src_a;
    logic [4:0] src_b;
    logic [4:0] src_c;
    logic [4:0] dst;
    logic gpr_write;
    logic mem_update;
    logic zero_a;
    logic use_imm;
    logic [31:0] imm;
    logic [31:0] mask;
    logic [4:0] shift;
    special_op_t special_op;
    fetch_fault_t fetch_fault;
    logic [31:0] branch_disp;
    logic branch_aa;
    logic branch_lk;
    logic [4:0] branch_bo;
    logic [4:0] branch_bi;
    logic [9:0] spr;
    logic [3:0] sr_index;
    logic sr_indexed;
    logic [2:0] cr_field;
    logic [2:0] cr_source_field;
    logic write_cr_fields;
    logic [7:0] cr_mask;
    logic write_cr_bit;
    logic [4:0] cr_bit;
    logic [4:0] cr_bit_a;
    logic [4:0] cr_bit_b;
    cr_logic_op_t cr_logic;
    mem_size_t mem_size;
    logic mem_signed;
    logic mem_reverse;
    // Register bytes fill from the most significant end; a load clears the
    // rest. mem_bytes counts them, 0 meaning 4.
    logic mem_left;
    logic [1:0] mem_bytes;
    mem_seq_t mem_seq;
    // lwarx / stwcx.
    logic mem_reserve;
    logic mem_conditional;
    // eciwx / ecowx.
    logic mem_external;
    // Completes without a memory access.
    logic mem_skip;
    // Not the last micro-op of its instruction.
    logic seq_partial;
    // dcbf/dcbst/dcbi/dcbz: translate and check like the access, no transfer.
    logic cache_probe;
    // dcbz: a translated probe that ends in the alignment exception.
    logic block_zero;
    // Data-cache operation of a cache-block instruction.
    cache_op_t cache_op;
    logic privileged;
    // Low 17 bits of alignment DSISR; reserved high bits are always zero.
    logic [16:0] alignment_dsisr;
    logic read_ca;
    logic read_so;
    logic needs_flags;
    logic write_xer;
    logic write_ca;
    logic write_ov_so;
    logic write_cr_field;
  } uop_t;
  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] insn;
    logic illegal;
    // Precise resumable alignment event; the instruction has no data effects.
    logic alignment_exception;
    // A recognized synchronous data fault is a precise exception, not illegal.
    data_fault_t data_fault;
    // A nonzero cause denotes a fetch event, not an executed instruction.
    // illegal distinguishes unsupported/disabled diagnostics from ISI entry.
    fetch_fault_t fetch_fault;
    page_miss_t page_miss;
    logic gpr_write;
    // Tracks a reserved rename slot even when a late fault suppresses writeback.
    logic rename_owned;
    logic [4:0] gpr;
    rename_tag_t tag;
    logic [31:0] value;
    logic update_write;
    logic [4:0] update_gpr;
    logic [31:0] update_value;
    logic needs_flags;
    logic write_xer;
    logic write_ca;
    logic write_ov_so;
    logic write_cr_field;
    logic [2:0] cr_field;
    logic write_cr_fields;
    logic [7:0] cr_mask;
    logic write_cr_bit;
    logic [4:0] cr_bit;
    logic [31:0] cr_delta;
    logic [31:0] xer_delta;
    // More micro-ops of this instruction follow; the PC does not advance.
    logic seq_partial;
  } retire_packet_t;

  // ---- MSR and exception events -------------------------------------------
  // HDL bit = 31 - manual bit.
  localparam int MSR_AP   = 23;  // 602 only
  localparam int MSR_SA   = 22;  // 602 only
  localparam int MSR_POW  = 18;
  localparam int MSR_TGPR = 17;
  localparam int MSR_ILE  = 16;
  localparam int MSR_EE   = 15;
  localparam int MSR_PR   = 14;
  localparam int MSR_FP   = 13;
  localparam int MSR_ME   = 12;
  localparam int MSR_SE   = 10;
  localparam int MSR_BE   = 9;
  localparam int MSR_IP   = 6;
  localparam int MSR_IR   = 5;
  localparam int MSR_DR   = 4;
  localparam int MSR_RI   = 1;
  localparam int MSR_LE   = 0;
  // Named 603e fields. Reserved bits read as zero and are never stored.
  localparam logic [31:0] MSR_IMPLEMENTED_MASK = 32'h0007_ff73;
  // SRR1 bits copied from MSR on entry and restored by rfi: manual 0, 5-9, 16-31.
  localparam logic [31:0] MSR_SRR1_MASK = 32'h87c0_ffff;
  // Hard reset: IP=1 (UM 4.5.1).
  localparam logic [31:0] MSR_RESET = 32'h0000_0040;
  // 602 AP and SA (602UM Table 2-1). Exception entry clears them and does
  // not save them in SRR1 (602UM Table 4-8); rfi restores them from SRR1.
  localparam logic [31:0] MSR_602_MASK = 32'h00c0_0000;

  function automatic logic [31:0] rfi_msr(
    input logic [31:0] old_msr,
    input logic [31:0] saved_srr1,
    input logic [31:0] implemented = MSR_IMPLEMENTED_MASK
  );
    logic [31:0] next_msr;
    next_msr = ((old_msr & ~MSR_SRR1_MASK) | (saved_srr1 & MSR_SRR1_MASK)) &
               implemented;
    // rfi always clears the 603e TGPR bit.
    next_msr[MSR_TGPR] = 1'b0;
    return next_msr;
  endfunction

  typedef enum logic [4:0] {
    EVENT_SC              = 5'd0,
    EVENT_PROGRAM_ILLEGAL = 5'd1,
    EVENT_PROGRAM_PRIV    = 5'd2,
    EVENT_RFI             = 5'd3,
    EVENT_ALIGNMENT       = 5'd4,
    EVENT_ISI             = 5'd5,
    EVENT_EXTERNAL        = 5'd6,
    EVENT_DECREMENTER     = 5'd7,
    EVENT_DSI             = 5'd8,
    EVENT_TLB_I_MISS      = 5'd9,
    EVENT_TLB_D_LOAD      = 5'd10,
    EVENT_TLB_D_STORE     = 5'd11,
    EVENT_MACHINE_CHECK   = 5'd12,
    EVENT_TRACE           = 5'd13,
    EVENT_IABR            = 5'd14,
    EVENT_PROGRAM_TRAP    = 5'd15,
    EVENT_FP_UNAVAILABLE  = 5'd16,
    // Pin-driven asynchronous events.
    EVENT_SOFT_RESET      = 5'd17,
    EVENT_SMI             = 5'd18,
    EVENT_MACHINE_CHECK_PIN = 5'd19,
    EVENT_MACHINE_CHECK_APE = 5'd20,
    // 602 only.
    EVENT_EMULATION_TRAP  = 5'd21,
    EVENT_ESA             = 5'd22,
    EVENT_DSA             = 5'd23
  } exception_event_t;

  // Chip-pin events into the core, already synchronized. soft_reset and mcp
  // are latched edges held until pin_status_t acknowledges them; smi and
  // tlbisync are levels.
  typedef struct packed {
    logic mcp;
    logic soft_reset;
    logic smi;
    logic tlbisync;
    // Latched bus error on a posted data-cache write or late fill beat;
    // held until tea_taken.
    logic tea;
    // Latched snoop address parity error; held until ape_taken.
    logic ape;
  } pin_event_t;
  // Core state the chip pins need.
  typedef struct packed {
    logic reservation;       // RSRV
    logic mcp_enable;        // HID0[EMCP]
    logic machine_check_enable; // MSR[ME]
    logic mcp_taken;         // pulses when a latched MCP is consumed
    logic soft_reset_taken;  // pulses when a latched SRESET is consumed
    logic smi_taken;
    logic tea_taken;
    // HID0 data-cache controls, as levels.
    logic dcache_enable;     // DCE
    logic dcache_lock;       // DLOCK
    logic dcache_flash_invalidate; // DCFI
    logic noop_touch;        // NOOPTI
    logic broadcast_enable;  // ABE
    logic address_parity_enable; // EBA
    logic ape_taken;
  } pin_status_t;
  // Data-cache BIU ports (docs/DATA_CACHE.md) bundled for the core
  // composition, between the cache slot and the BIU.
  typedef struct packed {
    logic         req_valid;
    logic [2:0]   req_kind;
    logic [4:0]   req_tt;
    logic [31:0]  req_addr;
    logic [7:0]   req_be;
    logic [3:0]   req_wimg;
    logic         req_gbl;
    logic [1:0]   req_cse;
    logic [255:0] req_data;
    logic         push_valid;
    logic [31:0]  push_addr;
    logic [255:0] push_data;
    logic         snoop_rsp_valid;
    logic         snoop_rsp_artry;
    logic         snoop_rsp_hit;
    logic         snoop_rsp_push;
  } dcache_bus_out_t;
  typedef struct packed {
    logic         req_ready;
    logic         rd_valid;
    logic [63:0]  rd_data;
    logic         rd_error;
    logic         wr_done;
    logic         wr_error;
    logic         push_ready;
    logic         push_done;
    logic         push_error;
    logic         snoop_valid;
    logic [31:0]  snoop_addr;
    logic [4:0]   snoop_tt;
  } dcache_bus_in_t;
  // ---- end MSR and exception events ---------------------------------------

  // ---- CPU variant configuration ------------------------------------------
  // The part the core models. EC603e is the PID7v-603e without the FPU.
  typedef enum logic [2:0] {
    CPU_PID7V_603E = 3'd0,
    CPU_PID6_603E = 3'd1,
    CPU_EC603E = 3'd2,
    CPU_603 = 3'd3,
    CPU_602 = 3'd4
  } cpu_variant_e;
  typedef enum logic [1:0] { FPU_NONE, FPU_DP, FPU_602_SP } fpu_kind_e;
  typedef struct packed {
    logic [31:0] pvr;
    logic [5:0]  div_latency;          // divw/divwu cycles (UM Table 6-4)
    logic [7:0]  icache_sets, dcache_sets;
    logic [2:0]  icache_ways, dcache_ways;
    logic [5:0]  tlb_sets;             // per I or D TLB, two ways
    logic [31:0] hid0_wmask, hid0_rmask;
    logic [31:0] hid1_rmask;           // PLL_CFG; HID1 is read-only
    logic        has_hid1, has_ear, has_srr1_key, has_abe_ifem;
    logic        misaligned_le_hw;     // misaligned LE single access in hardware
    logic        misaligned_ecxwx_hw;  // misaligned eciwx/ecowx in hardware
    logic        store_two_cycle;      // 2:2 stores
    logic        mul_602_timing;
    logic        has_602_ext;          // esa/dsa/mfrom, IBR, TCR, ESA SPRs, MSR AP/SA, PO
    logic        string_emulation_trap;
    logic        has_direct_store;     // T=1 segments use the XATS protocol
    fpu_kind_e   fpu;
  } cpu_cfg_t;
  // PID7v HID0: EMCP..NHR, ICE..DCFI, IFEM, FBIOB, ABE, NOOPTI (UM Table 2-2).
  localparam logic [31:0] HID0_MASK_PID7V = 32'hbff9_fc99;
  // PID6 lacks IFEM (bit 24) and ABE (bit 28).
  localparam logic [31:0] HID0_MASK_PID6 = 32'hbff9_fc11;
  // 602 (602UM Table 2-7): EMCP, SBCLK, ECLK, DOZE, NAP, SLEEP, DPM, RISEG,
  // NHR, DCE, ILOCK, DLOCK, ICFI, DCFI, PO, SL (bit 26 per the table; the
  // figure draws it at 25), WIMG. No ICE.
  localparam logic [31:0] HID0_MASK_602 = 32'h8af9_7caf;
  function automatic cpu_cfg_t cpu_cfg(cpu_variant_e v);
    cpu_cfg_t c;
    c.pvr = 32'h0007_0101;
    c.div_latency = 6'd20;
    c.icache_sets = 8'd128;
    c.dcache_sets = 8'd128;
    c.icache_ways = 3'd4;
    c.dcache_ways = 3'd4;
    c.tlb_sets = 6'd32;
    c.hid0_wmask = HID0_MASK_PID7V;
    c.hid0_rmask = HID0_MASK_PID7V;
    c.hid1_rmask = 32'hf000_0000;
    c.has_hid1 = 1'b1;
    c.has_ear = 1'b1;
    c.has_srr1_key = 1'b1;
    c.has_abe_ifem = 1'b1;
    c.misaligned_le_hw = 1'b1;
    c.misaligned_ecxwx_hw = 1'b0;
    c.store_two_cycle = 1'b0;
    c.mul_602_timing = 1'b0;
    c.has_602_ext = 1'b0;
    c.string_emulation_trap = 1'b0;
    c.has_direct_store = 1'b0;
    c.fpu = FPU_DP;
    case (v)
      CPU_PID6_603E: begin
        c.pvr = 32'h0006_0101;
        c.div_latency = 6'd37;
        c.hid0_wmask = HID0_MASK_PID6;
        c.hid0_rmask = HID0_MASK_PID6;
        c.has_abe_ifem = 1'b0;
        c.misaligned_le_hw = 1'b0;
        c.misaligned_ecxwx_hw = 1'b1;
      end
      CPU_EC603E: c.fpu = FPU_NONE;
      CPU_603: begin
        c.pvr = 32'h0003_0101;
        c.div_latency = 6'd37;
        c.icache_ways = 3'd2;
        c.dcache_ways = 3'd2;
        c.hid0_wmask = HID0_MASK_PID6;
        c.hid0_rmask = HID0_MASK_PID6;
        c.hid1_rmask = 32'h0;
        c.has_hid1 = 1'b0;
        c.has_srr1_key = 1'b0;
        c.has_abe_ifem = 1'b0;
        c.misaligned_le_hw = 1'b0;
        c.misaligned_ecxwx_hw = 1'b1;
        c.store_two_cycle = 1'b1;
        c.has_direct_store = 1'b1;
      end
      CPU_602: begin
        c.pvr = 32'h0005_0101;
        c.div_latency = 6'd37;
        c.icache_sets = 8'd64;
        c.dcache_sets = 8'd64;
        c.icache_ways = 3'd2;
        c.dcache_ways = 3'd2;
        c.tlb_sets = 6'd16;
        c.hid0_wmask = HID0_MASK_602;
        c.hid0_rmask = HID0_MASK_602;
        c.has_ear = 1'b0;
        c.has_abe_ifem = 1'b0;
        c.misaligned_le_hw = 1'b0;
        c.mul_602_timing = 1'b1;
        c.has_602_ext = 1'b1;
        c.string_emulation_trap = 1'b1;
        c.fpu = FPU_602_SP;
      end
      default: ;
    endcase
    return c;
  endfunction
  // Scalar fields for parameter expressions, where Quartus 18.1 cannot
  // select a member of a struct constant. Each reads one field of the record.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic int cpu_div_latency(cpu_variant_e v);
    cpu_cfg_t c;
    c = cpu_cfg(v);
    return int'(c.div_latency);
  endfunction
  function automatic int cpu_tlb_sets(cpu_variant_e v);
    cpu_cfg_t c;
    c = cpu_cfg(v);
    return int'(c.tlb_sets);
  endfunction
  function automatic bit cpu_has_602_ext(cpu_variant_e v);
    cpu_cfg_t c;
    c = cpu_cfg(v);
    return c.has_602_ext;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  // MSR bits the variant stores.
  function automatic logic [31:0] msr_implemented(logic has_602_ext);
    return MSR_IMPLEMENTED_MASK | (has_602_ext ? MSR_602_MASK : 32'b0);
  endfunction
  // 602 mfrom ROM: 7-bit round(256 * log10(1 + 10^(-i/256))) for i < 602,
  // zero beyond (602UM 2.3.7). The table falls monotonically, so entry i
  // counts the steps above i; MFROM_STEP[v-1] is the first index below v.
  localparam logic [9:0] MFROM_STEP [77] = '{
    10'd601, 10'd478, 10'd421, 10'd383, 10'd355, 10'd332, 10'd313, 10'd296,
    10'd282, 10'd269, 10'd258, 10'd247, 10'd237, 10'd228, 10'd220, 10'd212,
    10'd204, 10'd197, 10'd191, 10'd184, 10'd178, 10'd172, 10'd167, 10'd161,
    10'd156, 10'd151, 10'd146, 10'd142, 10'd137, 10'd133, 10'd129, 10'd125,
    10'd121, 10'd117, 10'd113, 10'd109, 10'd106, 10'd102, 10'd99, 10'd95,
    10'd92, 10'd89, 10'd85, 10'd82, 10'd79, 10'd76, 10'd73, 10'd70, 10'd68,
    10'd65, 10'd62, 10'd59, 10'd57, 10'd54, 10'd51, 10'd49, 10'd46, 10'd44,
    10'd41, 10'd39, 10'd37, 10'd34, 10'd32, 10'd30, 10'd27, 10'd25, 10'd23,
    10'd21, 10'd18, 10'd16, 10'd14, 10'd12, 10'd10, 10'd8, 10'd6, 10'd4,
    10'd2};
  function automatic logic [6:0] mfrom_rom(input logic [9:0] index);
    logic [6:0] value;
    value = '0;
    for (int v = 0; v < 77; v++)
      if (index < MFROM_STEP[v]) value = value + 7'd1;
    return value;
  endfunction
  // Variants whose differences from the PID7v are all implemented.
  function automatic bit cpu_variant_supported(cpu_variant_e v);
    return (v == CPU_PID7V_603E) || (v == CPU_PID6_603E) || (v == CPU_EC603E);
  endfunction
  // PLL_CFG[0:3] codes the variant's PLL accepts, clock-off excluded. PID6:
  // UM Table 7-10. PID7v and EC603e: Table 7-10 without 1:1 and 1.5:1 (UM
  // 1.1); their 4.5:1-6:1 codes are not given in the UM. 603: Table C-4.
  // 602: 602HW Table 11.
  // Bit n of each mask accepts code n (Quartus 18.1 has no set membership).
  function automatic bit pll_cfg_legal(cpu_variant_e v, logic [3:0] code);
    logic [15:0] codes;
    case (v)
      // 0000-0110, 1000, 1010, 1100, 1110
      CPU_PID6_603E: codes = 16'b0101_0101_0111_1111;
      // 0000-0101, 1000, 1001, 1100
      CPU_603:       codes = 16'b0001_0011_0011_1111;
      // 0100, 0101, 1000, 1001
      CPU_602:       codes = 16'b0000_0011_0011_0000;
      // 0011-0110, 1000, 1010, 1110
      default:       codes = 16'b0100_0101_0111_1000;
    endcase
    return codes[code];
  endfunction
  // Codes that run the bus at the core clock: the 1:1 rows and PLL bypass.
  function automatic bit pll_cfg_bus_1to1(logic [3:0] code);
    return code <= 4'b0011;
  endfunction
  // The core runs 1:1 with the bus. PID7v and EC603e have no 1:1 ratio, so
  // their only such code is PLL bypass; the 602 has none.
  function automatic logic [3:0] pll_cfg_default(cpu_variant_e v);
    return ((v == CPU_PID7V_603E) || (v == CPU_EC603E)) ? 4'b0011 : 4'b0000;
  endfunction
  // ---- end CPU variant configuration --------------------------------------

  // ---- SPR write masks and reset values -----------------------------------
  // Hard reset clears all three (UM Table 4-8).
  // SDR1: HTABORG manual 0-15, reserved 16-22, HTABMASK 23-31. Reserved bits
  // are never stored, so they read as zero.
  localparam logic [31:0] SDR1_WMASK = 32'hffff_01ff;
  localparam logic [31:0] SDR1_RESET = 32'h0000_0000;
  // DSISR and SPRG0-3 are fully architected; no mask needed.
  localparam logic [31:0] DSISR_RESET = 32'h0000_0000;
  // HID0 (UM Table 2-2): every named bit of the variant is stored
  // (cpu_cfg().hid0_wmask); reserved bits read as zero. ICE and ICFI act
  // (instruction cache), and EMCP on the chip top; the rest have no
  // implemented feature to control. Hard reset clears HID0 and HID1.
  localparam int HID0_ICE = 15;
  localparam int HID0_ICFI = 11;
  localparam int HID0_DCE = 14;
  localparam int HID0_DLOCK = 12;
  localparam int HID0_DCFI = 10;
  localparam int HID0_ABE = 3;
  localparam int HID0_NOOPTI = 0;
  localparam int HID0_EMCP = 31;
  localparam int HID0_EBA = 29;
  // EAR: E (manual bit 0) and RID (manual bits 28-31, UM 2.1.1).
  localparam logic [31:0] EAR_WMASK = 32'h8000_000f;
  // 602 SPRs (602UM 2.1.2.3-4); SER, SP and LT are fully defined. Hard
  // reset clears IBR (2.1.2.4.3); the rest reset to zero here, which for SP
  // and LT is a simulation choice, not a silicon value (2.1.2.4.1).
  localparam logic [31:0] TCR_WMASK = 32'hfe00_0000;     // TI, CRE, L2E, NWE, WIE, SLT
  localparam logic [31:0] IBR_WMASK = 32'hffff_0000;
  localparam logic [31:0] ESASRR_WMASK = 32'h0000_000f;  // PR, AP, SA, EE
  localparam logic [31:0] SEBR_WMASK = 32'hfffe_0000;
  localparam int EAR_E = 31;
  localparam logic [31:0] SPRG_RESET = 32'h0000_0000;
  // ---- end SPR write masks and reset values -------------------------------
endpackage
/* verilator lint_on UNUSEDPARAM */
`default_nettype wire
