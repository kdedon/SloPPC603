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
    SPECIAL_FPU, SPECIAL_FP_UNAVAILABLE
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

  function automatic logic [31:0] rfi_msr(
    input logic [31:0] old_msr,
    input logic [31:0] saved_srr1
  );
    logic [31:0] next_msr;
    next_msr = ((old_msr & ~MSR_SRR1_MASK) | (saved_srr1 & MSR_SRR1_MASK)) &
               MSR_IMPLEMENTED_MASK;
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
    EVENT_MACHINE_CHECK_APE = 5'd20
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

  // ---- SPR write masks and reset values -----------------------------------
  // Hard reset clears all three (UM Table 4-8).
  // SDR1: HTABORG manual 0-15, reserved 16-22, HTABMASK 23-31. Reserved bits
  // are never stored, so they read as zero.
  localparam logic [31:0] SDR1_WMASK = 32'hffff_01ff;
  localparam logic [31:0] SDR1_RESET = 32'h0000_0000;
  // DSISR and SPRG0-3 are fully architected; no mask needed.
  localparam logic [31:0] DSISR_RESET = 32'h0000_0000;
  // HID0 (UM Table 2-2): every named PID7v bit is stored; reserved bits read
  // as zero. ICE and ICFI act (instruction cache), and EMCP on the chip top;
  // the rest have no implemented feature to control. Hard reset clears HID0 and HID1.
  localparam logic [31:0] HID0_WMASK = 32'hbff9_fc99;
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
  localparam int EAR_E = 31;
  localparam logic [31:0] SPRG_RESET = 32'h0000_0000;
  // ---- end SPR write masks and reset values -------------------------------
endpackage
/* verilator lint_on UNUSEDPARAM */
`default_nettype wire
