package ppc_pkg;
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
  // Synchronous data-translation faults. Transport errors remain separate.
  typedef enum logic [2:0] {
    DATA_OK = 3'd0,
    DATA_DSI_PROTECTION = 3'd1,
    DATA_PAGE_MISS = 3'd2,
    DATA_PAGE_CHANGED = 3'd3
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
  // Synchronous translation faults. Bus TEA takes the transport-fatal path.
  typedef enum logic [2:0] {
    FETCH_OK = 3'd0,
    FETCH_ISI_PROTECTION = 3'd1,
    FETCH_ISI_GUARDED = 3'd2,
    FETCH_PAGE_MISS = 3'd3
  } fetch_fault_t;
  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] insn;
    fetch_fault_t fault;
    page_miss_t page_miss;
  } fetch_packet_t;
  typedef enum logic [4:0] {
    ALU_ADD, ALU_OR, ALU_XOR, ALU_AND, ALU_ANDC,
    ALU_ORC, ALU_NAND, ALU_NOR, ALU_EQV, ALU_ADDC, ALU_ADDE,
    ALU_ADDME, ALU_ADDZE, ALU_ROTATE, ALU_SLW, ALU_SRW, ALU_SRAW,
    ALU_RLWIMI, ALU_SUBF, ALU_SUBFC, ALU_SUBFE,
    ALU_CNTLZW, ALU_EXTSB, ALU_EXTSH, ALU_MULLW,
    ALU_MULHW, ALU_MULHWU, ALU_DIVWU, ALU_DIVW, ALU_MULLI
  } alu_op_t;
  typedef enum logic [4:0] {
    SPECIAL_NONE, SPECIAL_B, SPECIAL_BC, SPECIAL_BCLR, SPECIAL_BCCTR,
    SPECIAL_MFSPR, SPECIAL_MTSPR, SPECIAL_CMP, SPECIAL_CMPL,
    SPECIAL_LOAD, SPECIAL_STORE, SPECIAL_MFCR, SPECIAL_MTCRF,
    SPECIAL_CR_LOGIC, SPECIAL_MCRF, SPECIAL_MCRXR,
    SPECIAL_SC, SPECIAL_RFI, SPECIAL_PROGRAM_ILLEGAL,
    SPECIAL_PROGRAM_PRIV, SPECIAL_MFMSR,
    SPECIAL_ISYNC, SPECIAL_SYNC, SPECIAL_EIEIO, SPECIAL_ALIGNMENT, SPECIAL_ISI, SPECIAL_MTMSR,
    SPECIAL_MFSR, SPECIAL_MTSR, SPECIAL_TLBIE,
    SPECIAL_TLBLD, SPECIAL_TLBLI
  } special_op_t;
  typedef enum logic [2:0] {
    CR_LOGIC_AND, CR_LOGIC_ANDC, CR_LOGIC_EQV, CR_LOGIC_NAND,
    CR_LOGIC_NOR, CR_LOGIC_OR, CR_LOGIC_ORC, CR_LOGIC_XOR
  } cr_logic_op_t;
  typedef enum logic [1:0] {
    MEM_BYTE, MEM_HALF, MEM_WORD
  } mem_size_t;
  // Unit benches elaborate subsets of the package constants below.
  /* verilator lint_off UNUSEDPARAM */
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
  // XER
  localparam int XER_SO_BIT = 31;
  localparam int XER_CA_BIT = 29;
  localparam int XER_BYTE_COUNT_WIDTH = 7;
  localparam logic [31:0] XER_IMPLEMENTED_MASK = 32'he000_007f;
  /* verilator lint_on UNUSEDPARAM */
  typedef struct packed {
    alu_op_t op;
    logic [31:0] a;
    logic [31:0] b;
    logic [31:0] mask;
    logic [4:0] shift;
    logic ca_in;
    logic so_in;
    logic write_ca;
    logic write_ov_so;
    logic write_cr0;
    completion_tag_t producer;
  } issue_packet_t;
  typedef struct packed {
    alu_op_t op;
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
    // Low 17 bits of alignment DSISR; reserved high bits are always zero.
    logic [16:0] alignment_dsisr;
    logic read_ca;
    logic read_so;
    logic needs_flags;
    logic write_xer;
    logic write_ca;
    logic write_ov_so;
    logic write_cr0;
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
    logic write_cr0;
    logic [2:0] cr_field;
    logic write_cr_fields;
    logic [7:0] cr_mask;
    logic write_cr_bit;
    logic [4:0] cr_bit;
    logic [31:0] cr_delta;
    logic [31:0] xer_delta;
  } retire_packet_t;
endpackage
