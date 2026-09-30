// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
module ppc_fpu #(
    parameter bit CPU_602 = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,
    input logic issue_valid_i,
    output logic issue_ready_o,
    input ppc_fpu_pkg::ppc_fpu_issue_t issue_i,
    input logic issue1_valid_i,
    output logic issue1_ready_o,
    input ppc_fpu_pkg::ppc_fpu_issue_t issue1_i,
    output logic result_valid_o,
    output ppc_fpu_pkg::ppc_fpu_result_t result_o,
    output logic result1_valid_o,
    output ppc_fpu_pkg::ppc_fpu_result_t result1_o,
    input logic commit_valid_i,
    input ppc_pkg::completion_tag_t commit_tag_i,
    output logic commit_ready_o,
    input logic commit1_valid_i,
    input ppc_pkg::completion_tag_t commit1_tag_i,
    output logic commit1_ready_o,
    input logic abort_valid_i,
    input ppc_pkg::completion_tag_t abort_tag_i,
    input logic kill_all_i,
    output logic mem_req_valid_o,
    input logic mem_req_ready_i,
    output ppc_fpu_pkg::ppc_fpu_mem_t mem_req_o,
    input logic mem_rsp_valid_i,
    output logic mem_rsp_ready_o,
    input ppc_fpu_pkg::ppc_fpu_mem_rsp_t mem_rsp_i,
    output logic store_valid_o,
    input logic store_ready_i,
    output ppc_fpu_pkg::ppc_fpu_mem_t store_o,
    input logic [4:0] inspect_fpr_index_i,
    output logic [63:0] inspect_fpr_o,
    output logic [31:0] inspect_fpscr_o,
    output logic [31:0] inspect_sp_o,
    output logic [31:0] inspect_lt_o,
    output logic forward_valid_o,
    output ppc_fpu_pkg::ppc_fpu_forward_t forward_o,
    output logic forward1_valid_o,
    output ppc_fpu_pkg::ppc_fpu_forward_t forward1_o,
    output ppc_fpu_pkg::ppc_fpu_forward_data_t forward_data_o,
    output ppc_fpu_pkg::ppc_fpu_forward_data_t forward1_data_o
);
  import ppc_pkg::completion_tag_t;
  import ppc_fpu_pkg::*;
  import ppc_fpu_arith_pkg::operand_602;
  import ppc_fpu_arith_pkg::word_602;
  import ppc_fpu_arith_pkg::fits_602;

  localparam int PENDING_DEPTH = CPU_602 ? 4 : 5;
  localparam int PENDING_IDX_BITS = CPU_602 ? 2 : 3;
  localparam int FPR_BITS = CPU_602 ? 32 : 64;

  typedef enum logic [3:0] {
    DK_ILLEGAL, DK_ARITH, DK_MOVE, DK_FSEL, DK_MFFS, DK_MCRFS,
    DK_MTFS, DK_MEMORY, DK_MFSPR, DK_MTSPR
  } decode_kind_t;
  typedef struct packed {
    decode_kind_t kind;
    ppc_fpu_op_t op;
    logic single_result;
    logic mem_load;
    logic mem_store;
    logic mem_single;
    logic mem_integer;
    logic mem_update;
    logic [1:0] move_kind;
    logic spr_sp;
  } decoded_t;

  typedef struct packed {
    decoded_t decoded;
    logic [31:0] ea;
  } decode_info_t;

  typedef struct packed {
    logic ready;
    logic fwd;
    logic [63:0] raw;
    logic sp;
    logic lt;
    logic selb;
  } source_t;
  typedef struct packed {
    logic [63:0] raw;
    logic sp;
  } local_operand_t;
  // Arithmetic status kept until retirement; the value lives in `value`.
  typedef struct packed {
    logic write_result;
    logic [8:0] invalid;
    logic ox;
    logic ux;
    logic zx;
    logic xx;
    logic fr;
    logic fi;
    logic frfi_valid;
    logic [4:0] fprf;
    logic fprf_valid;
    logic [3:0] fpcc;
    logic compare_valid;
    logic tiny_before_round;
  } arith_flags_t;
  // Result disposition. Tag, indices and addresses come from the issue
  // record; the one data word is in `value`.
  typedef struct packed {
    ppc_fpu_exception_t exception;
    logic [3:0] fault_code;
    logic fpr_write;
    logic fpr_sp;
    logic fpr_lt;
    logic fpscr_write;
    logic cr_write;
    logic [2:0] cr_field;
    logic [3:0] cr_value;
    logic gpr_update;
    logic store;
  } status_t;
  typedef struct packed {
    logic valid;
    logic started;
    logic done;
    logic finishing;
    logic dest_fpr;
    ppc_fpu_issue_t issue;
    decoded_t decoded;
    // First lookup's register: frS for a load or store, else frA.
    logic [4:0] src_a;
    // fsel class of that register's architectural value, kept current.
    logic a_class;
    logic [31:0] ea;
    status_t st;
    // FPR result, store data, fault information, proposed FPSCR or SPR
    // read, by instruction kind.
    logic [63:0] value;
    arith_flags_t arith;
    logic arith_done;
    logic fpr_forwarded;
    logic cr_forwarded;
    logic [1:0] local_wait;
    logic mem_write;
    logic store_fill;
    // Producer slot of each source (frA or frS, frB, frC), bound at
    // dispatch; zero reads the register file.
    logic [2:0][PENDING_DEPTH-1:0] producer;
  } pending_t;
  typedef struct packed {
    logic record;
    status_t st;
    logic [1:0] local_wait;
    logic mem_write;
    logic store_fill;
    logic value_write;
  } launch_t;
  typedef struct packed {
    logic valid;
    completion_tag_t tag;
    logic is_move;
    logic rc;
    logic [1:0] move_kind;
    local_operand_t a;
    local_operand_t b;
    local_operand_t c;
    logic c_lt;
    logic [2:0] fwd;
  } local_stage_t;
  typedef struct packed {
    completion_tag_t tag;
    logic [31:0] insn;
    logic msr_fp;
    logic msr_fe0;
    logic msr_fe1;
    logic msr_pr;
  } work_t;
  typedef struct packed {
    completion_tag_t tag;
    logic [31:0] insn;
    logic msr_fp;
  } work1_t;

  typedef struct packed {
    completion_tag_t tag;
    logic fpr_write;
    logic [4:0] fpr_index;
    logic [63:0] fpr_value;
    logic fpr_sp;
    logic fpr_lt;
    logic cr_write;
    logic [2:0] cr_field;
    logic [3:0] cr_value;
    logic reply;
    logic [31:0] prefix;
    logic fctiwz;
    // fpr_value holds the stored value; an arriving value replaces it
    // after the bus pick.
    logic rsp_value;
    logic load_value;
    logic load_single;
  } forward_candidate_t;
  typedef struct packed {
    logic valid;
    logic reply;
    logic [31:0] prefix;
    logic fctiwz;
    ppc_fpu_forward_data_t data;
  } forward_payload_t;

  pending_t pending_q [0:PENDING_DEPTH-1];
  pending_t pending_d [0:PENDING_DEPTH-1];
  // Head and second-oldest entries.
  pending_t pv [0:1];
  logic [PENDING_IDX_BITS-1:0] head_q, head_d;
  logic [PENDING_IDX_BITS-1:0] head1_q, tail_q, tail1_q;
  // older_q[t][s]: slot t holds an older position than slot s.
  logic [PENDING_DEPTH-1:0] older_q [0:PENDING_DEPTH-1];
  logic [PENDING_IDX_BITS-1:0] arith_rsp_slot, mem_rsp_slot;
  logic [PENDING_IDX_BITS-1:0] exec_slot;
  local_stage_t local_stage_q;
  local_stage_t local_stage_d;
  logic [2:0] pending_count_q;
  logic [2:0] pending_count_d;
  logic [31:0] sp_q;
  logic [31:0] lt_q;
  logic [31:0] sp_d;
  logic [31:0] lt_d;
  decoded_t decoded;
  decoded_t decoded1;
  decode_info_t decode0;
  decode_info_t decode1;
  logic [31:0] issue1_ea;
  ppc_fpu_result_t head_result;
  ppc_fpu_result_t second_result;
  ppc_fpu_result_t exec_result;
  ppc_fpu_arith_req_t arith_req;
  ppc_fpu_arith_rsp_t arith_rsp;
  ppc_fpu_arith_rsp_t arith_finish;
  logic arith_req_ready;
  logic arith_rsp_valid;
  logic arith_rsp_held;
  logic arith_rsp_ready;
  logic arith_finish_valid;
  logic arith_finish_write;
  logic arith_next_finish_valid;
  completion_tag_t arith_next_finish_tag;
  logic [2:0] arith_req_fwd;
  local_operand_t local_a, local_b, local_c;
  source_t slot_src [0:PENDING_DEPTH-1];
  logic [2:0] fpr_count_q;
  logic [2:0] fpr_count_d;
  logic barrier_q;
  logic barrier_d;
  logic [1:0] fpr_we;
  logic [1:0][4:0] fpr_waddr;
  // Each FPR word carries its fsel class above the value.
  logic [1:0][FPR_BITS:0] fpr_wdata;
  logic [5:0][4:0] fpr_raddr;
  logic [5:0][FPR_BITS:0] fpr_rdata;
  logic [31:0] fpscr_q;
  logic [31:0] proposed_fpscr;
  logic [31:0] issue_ea;
  logic [63:0] src_a;
  logic [63:0] src_b;
  logic [63:0] src_c;
  logic src_d_bad, work1_d_bad;
  // A preparation offered and not accepted stays offered, even when its
  // stfd source, forwarded at the offer, turns out to trap.
  logic offer_q;
  completion_tag_t offer_tag_q;
  logic offer_held, work1_offer_held;
  logic store_d_ready, work1_store_d_ready;
  logic src_a_sp, src_b_sp, src_c_sp, src_d_sp;
  logic src_b_lt, src_d_lt;
  // Only operand a's fsel class is read.
  /* verilator lint_off UNUSEDSIGNAL */
  source_t source_a, source_b, source_c, source_d;
  /* verilator lint_on UNUSEDSIGNAL */
  logic use_a, use_b, use_c, use_d;
  logic select_b;
  logic operand_tags_ok;
  logic mem_sources_ready;
  logic mem_tags_ok;
  logic work_valid;
  logic head_available;
  logic [2:0] after_retire_count;
  logic matching_abort;
  logic duplicate_tag;
  logic duplicate1_tag;
  forward_candidate_t slot_candidate [0:PENDING_DEPTH-1];
  logic [31:0] slot_prefix [0:PENDING_DEPTH-1];
  logic [PENDING_DEPTH-1:0] fwd0_sel, fwd1_sel;
  logic [2:0] abort_index;
  logic [PENDING_DEPTH-1:0] abort_hit;
  logic [PENDING_DEPTH-1:0] aborted;
  logic abort_index_valid;
  logic safe_abort_flush;
  logic deferred_abort_flush_q;
  logic deferred_abort_flush;
  logic older_arith_pending;
  logic sources_ready;
  logic [2:0][PENDING_DEPTH-1:0] bind0, bind1;
  pending_t exec_entry, second_entry;
  logic [PENDING_DEPTH-1:0] exec_pick, second_pick;
  logic [2:0][4:0] work1_index;
  logic [1:0][2:0][4:0] lane_index;
  logic [1:0][2:0][PENDING_DEPTH-1:0] lane_writer;
  logic [PENDING_DEPTH-1:0] retiring;
  logic exec_found;
  logic second_exec_found;
  logic [PENDING_IDX_BITS-1:0] second_exec_slot;
  logic exec_kind_mem, exec_kind_fpu;
  logic exec_fire;
  logic arith_rsp_match;
  logic mem_rsp_match;
  logic arith_rsp_head, mem_rsp_head, mem_rsp_second;
  logic retire_fire;
  logic retire1_fire;
  logic [1:0] retire_count;
  logic dispatch_fire;
  logic dispatch1_fire;
  logic dec_exec, dec_mem, dec_write, dec1_exec, dec1_mem, dec1_write;
  logic pair_ok, ready_if_mem, ready_if_exec;
  logic retire_credit, retire_credit2, space_ok, space1_ok;
  logic fpr_ok, fpr1_ok;
  logic div_busy;
  logic barrier_present;
  logic source_waiting;
  forward_candidate_t fwd0;
  forward_candidate_t fwd1;
  forward_payload_t fwd0_payload_d, fwd0_payload_q;
  forward_payload_t fwd1_payload_d, fwd1_payload_q;
  work_t work_issue;
  decoded_t work_decoded;
  logic work_dispatch;
  logic work_admitted;
  logic [31:0] work_ea;
  logic [4:0] src_a_index, src_b_index, src_c_index;
  logic arith_launch;
  logic mem_launch;
  logic local_launch;
  logic arith_eligible;
  logic mem_eligible;
  logic local_fpu_uses_pipe;
  ppc_fpu_result_t mem_incoming_result;
  // Only the move/select value and disposition fields are read.
  /* verilator lint_off UNUSEDSIGNAL */
  ppc_fpu_result_t local_result;
  /* verilator lint_on UNUSEDSIGNAL */
  logic commit_match;
  logic abort_match;
  work1_t work1_issue;
  decoded_t work1_decoded;
  logic [31:0] work1_ea;
  logic work1_valid;
  logic work1_old;
  logic work1_admitted;
  // Only operand a's fsel class is read.
  /* verilator lint_off UNUSEDSIGNAL */
  source_t work1_a, work1_b, work1_c, work1_d;
  /* verilator lint_on UNUSEDSIGNAL */
  logic work1_use_a, work1_use_b, work1_use_c, work1_use_d;
  logic work1_sources_ready;
  logic work1_tags_ok;
  logic work1_mem_sources_ready;
  logic work1_mem_tags_ok;
  logic work1_mem_lane0_dep;
  logic work1_select_b;
  logic work1_lane0_dep;
  logic work1_arith_eligible;
  logic work1_mem_eligible;
  logic work1_local_launch;
  logic work1_arith_launch;
  logic work1_mem_launch;
  logic work1_fire;
  logic combined_arith_launch;
  logic arith_from_work;
  ppc_fpu_mem_t work1_mem_req;
  logic [63:0] mem_value;
  logic [63:0] launch_value;
  launch_t launch0, launch1;
  logic [63:0] work1_mem_value;
  logic mem_fill;
  logic work1_mem_fill;
  logic [63:0] reply_raw;
  // Arriving load data in stored format; a 602 double load traps unless
  // its value is a single.
  logic [63:0] load_single, load_double;
  logic load_fits;
  ppc_fpu_result_t work1_result;

  // One-hot oldest set slot.
  function automatic logic [PENDING_DEPTH-1:0] oldest_of(
      input logic [PENDING_DEPTH-1:0] set);
    logic [PENDING_DEPTH-1:0] out;
    begin
      for (integer s = 0; s < PENDING_DEPTH; s++) begin
        out[s] = set[s];
        for (integer t = 0; t < PENDING_DEPTH; t++)
          if (t != s && set[t] && older_q[t][s])
            out[s] = 1'b0;
      end
      return out;
    end
  endfunction

  // The oldest CR result takes the first bus and displaces the oldest
  // other result to the second; otherwise the two oldest go in order.
  // Returns {second, first}.
  function automatic logic [2*PENDING_DEPTH-1:0] forward_pick(
      input logic [PENDING_DEPTH-1:0] elig,
      input logic [PENDING_DEPTH-1:0] cr_new);
    logic [PENDING_DEPTH-1:0] e1, e2, cr_first;
    begin
      e1 = oldest_of(elig);
      e2 = oldest_of(elig & ~e1);
      cr_first = oldest_of(elig & cr_new);
      if (|cr_first) return {(cr_first == e1 ? e2 : e1), cr_first};
      return {e2, e1};
    end
  endfunction

  // One-hot youngest set slot.
  function automatic logic [PENDING_DEPTH-1:0] youngest_of(
      input logic [PENDING_DEPTH-1:0] set);
    logic [PENDING_DEPTH-1:0] out;
    begin
      for (integer s = 0; s < PENDING_DEPTH; s++) begin
        out[s] = set[s];
        for (integer t = 0; t < PENDING_DEPTH; t++)
          if (t != s && set[t] && older_q[s][t])
            out[s] = 1'b0;
      end
      return out;
    end
  endfunction

  // Physical slot of age k.
  function automatic logic [PENDING_IDX_BITS-1:0] slot_of(
      input logic [PENDING_IDX_BITS-1:0] head, input logic [2:0] k);
    logic [3:0] sum;
    begin
      sum = {{(4-PENDING_IDX_BITS){1'b0}},head} + {1'b0,k};
      if (CPU_602) sum[3:2] = 2'd0;
      else if (sum >= 4'd10) sum = sum - 4'd10;
      else if (sum >= 4'd5) sum = sum - 4'd5;
      return PENDING_IDX_BITS'(sum);
    end
  endfunction

  // Age of physical slot s.
  function automatic logic [2:0] age_of(
      input logic [PENDING_IDX_BITS-1:0] head,
      input logic [PENDING_IDX_BITS-1:0] s);
    logic [3:0] diff;
    begin
      diff = {{(4-PENDING_IDX_BITS){1'b0}},s} + 4'(PENDING_DEPTH) - {{(4-PENDING_IDX_BITS){1'b0}},head};
      if (diff >= 4'(PENDING_DEPTH)) diff = diff - 4'(PENDING_DEPTH);
      return diff[2:0];
    end
  endfunction

  function automatic logic [31:0] normalize_fpscr(input logic [31:0] f);
    logic [31:0] n;
    begin
      n = f;
      n[29] = |{f[24:19], f[10:8]};
      n[30] = (n[29] && f[7]) || (f[28] && f[6]) ||
              (f[27] && f[5]) || (f[26] && f[4]) || (f[25] && f[3]);
      n[11] = 1'b0;
      return n;
    end
  endfunction

  function automatic logic [31:0] arithmetic_fpscr(
      input logic [31:0] old_f,
      input logic [8:0] invalid,
      input logic ox,
      input logic ux,
      input logic zx,
      input logic xx,
      input logic fr,
      input logic fi,
      input logic frfi_valid,
      input logic [4:0] fprf,
      input logic fprf_valid,
      input logic [3:0] fpcc,
      input logic compare_valid
  );
    logic [31:0] n;
    logic changed;
    begin
      n = old_f;
      for (integer i = 0; i < 6; i++) n[24-i] = old_f[24-i] | invalid[i];
      for (integer i = 6; i < 9; i++) n[16-i] = old_f[16-i] | invalid[i];
      n[28] = old_f[28] | ox;
      n[27] = old_f[27] | ux;
      n[26] = old_f[26] | zx;
      n[25] = old_f[25] | xx;
      if (frfi_valid) begin
        n[18] = fr;
        n[17] = fi;
        n[25] = n[25] | fi;
      end
      if (compare_valid) n[15:12] = fpcc;
      else if (fprf_valid) n[16:12] = fprf;
      changed = |(n[28:19] & ~old_f[28:19]) ||
                |(n[10:8] & ~old_f[10:8]);
      n[31] = old_f[31] | changed;
      return normalize_fpscr(n);
    end
  endfunction

  function automatic logic [63:0] widen_single(input logic [31:0] s);
    logic [63:0] d;
    logic [22:0] frac;
    logic [7:0] exp;
    integer lead;
    begin
      d = '0;
      d[63] = s[31];
      frac = s[22:0];
      exp = s[30:23];
      if (exp == 8'hff) begin
        d[62:52] = 11'h7ff;
        d[51:29] = frac;
      end else if (exp != 8'd0) begin
        d[62:52] = 11'(int'(exp) + 896);
        d[51:29] = frac;
      end else if (frac != 23'd0) begin
        lead = 0;
        for (integer i = 0; i < 23; i++) begin
          if (frac[i]) lead = i;
        end
        d[62:52] = 11'(lead + 874);
        d[51:0] = (52'(frac) << $unsigned(52 - lead));
      end
      return d;
    end
  endfunction

  function automatic logic [63:0] store_data(input logic integer_word,
                                             input logic single,
                                             input logic [63:0] raw);
    if (CPU_602)
      return integer_word || single ? {32'd0, raw[31:0]} :
          operand_602(raw[31:0]);
    return integer_word ? {32'd0, raw[31:0]} :
        single ? {32'd0, narrow_single(raw)} : raw;
  endfunction

  function automatic logic [31:0] narrow_single(input logic [63:0] d);
    logic [31:0] s;
    logic [52:0] sig;
    integer exponent;
    integer shift_amt;
    begin
      s = '0;
      s[31] = d[63];
      exponent = int'(d[62:52]);
      if (exponent >= 897) begin
        s[30:23] = {d[62], d[58:52]};
        s[22:0] = d[51:29];
      end else if (exponent != 0) begin
        sig = {1'b1, d[51:0]};
        shift_amt = 29 + (897 - exponent);
        if (shift_amt < 53) s[22:0] = 23'(sig >> $unsigned(shift_amt));
      end
      return s;
    end
  endfunction

  // stfd needs a finite, non-denormal binary32 source.
  function automatic logic stfd_traps(input logic [30:0] w);
    return w[30:23] == 8'hff || (w[30:23] == 8'd0 && w[22:0] != 23'd0);
  endfunction

  function automatic logic single_fits_double(input logic [63:0] d);
    logic [31:0] s;
    begin
      s = narrow_single(d);
      return d[62:52] != 11'h7ff &&
          (s[30:23] != 8'd0 || s[22:0] == 23'd0) &&
          widen_single(s) == d;
    end
  endfunction

  function automatic logic is_barrier(input decode_kind_t kind,
                                       input ppc_fpu_op_t op);
    return kind == DK_MFFS || kind == DK_MCRFS ||
        kind == DK_MTFS || kind == DK_MFSPR || kind == DK_MTSPR ||
        (CPU_602 && kind == DK_ARITH && op == FP_FCTIWZ);
  endfunction

  function automatic logic [1:0] local_latency(input decode_kind_t kind);
    if (CPU_602 && kind == DK_MFSPR) return 2'd1;
    if (CPU_602 && kind == DK_MTSPR) return 2'd2;
    return 2'd3;
  endfunction

  // Moves, selects and FPSCR instructions finish in the third stage (Table
  // 6-5 1-1-1) and retire from the registered result like arithmetic; only
  // their dependents see the value a cycle earlier.
  function automatic logic spr_transfer(input decode_kind_t kind);
    return CPU_602 && (kind == DK_MFSPR || kind == DK_MTSPR);
  endfunction

  function automatic logic is_fpu_exec(input decode_kind_t kind);
    return kind == DK_ARITH || kind == DK_MOVE || kind == DK_FSEL;
  endfunction

  function automatic logic writes_fpr(input decode_kind_t kind,
                                       input ppc_fpu_op_t op,
                                       input logic mem_load);
    return (kind == DK_ARITH && op != FP_CMPU && op != FP_CMPO) ||
        kind == DK_MOVE || kind == DK_FSEL || kind == DK_MFFS ||
        (kind == DK_MEMORY && mem_load);
  endfunction

  function automatic logic numeric_emulation_trap(
      input logic [8:0] invalid, input logic ox, input logic ux,
      input logic zx, input logic xx, input logic tiny,
      input logic [5:0] control
  );
    logic enabled;
    begin
      enabled = ((|invalid) && control[5]) || (ox && control[4]) ||
          (ux && control[3]) || (zx && control[2]) || (xx && control[1]);
      return CPU_602 && (enabled || (!control[0] && tiny));
    end
  endfunction

  // Field extractors: each reads only part of its record.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic arith_flags_t flags_of(input ppc_fpu_arith_rsp_t ar);
    arith_flags_t f;
    f.write_result = ar.write_result;
    f.invalid = ar.invalid;
    f.ox = ar.ox;
    f.ux = ar.ux;
    f.zx = ar.zx;
    f.xx = ar.xx;
    f.fr = ar.fr;
    f.fi = ar.fi;
    f.frfi_valid = ar.frfi_valid;
    f.fprf = ar.fprf;
    f.fprf_valid = ar.fprf_valid;
    f.fpcc = ar.fpcc;
    f.compare_valid = ar.compare_valid;
    f.tiny_before_round = ar.tiny_before_round;
    return f;
  endfunction

  function automatic logic flags_trap(input arith_flags_t ar,
                                      input logic [31:0] f);
    return numeric_emulation_trap(ar.invalid, ar.ox, ar.ux, ar.zx, ar.xx,
                                  ar.tiny_before_round, f[7:2]);
  endfunction

  function automatic logic [31:0] flags_fpscr(input logic [31:0] old_f,
                                              input arith_flags_t ar);
    return arithmetic_fpscr(old_f, ar.invalid, ar.ox, ar.ux, ar.zx, ar.xx,
        ar.fr, ar.fi, ar.frfi_valid, ar.fprf, ar.fprf_valid, ar.fpcc,
        ar.compare_valid);
  endfunction

  /* verilator lint_on UNUSEDSIGNAL */

  // Stored format of the registered arithmetic reply.
  function automatic logic [63:0] format_reply(input ppc_fpu_op_t op);
    return CPU_602 ? {32'd0, (op == FP_FCTIWZ ? arith_rsp.result[31:0] :
        reply_raw[31:0])} : arith_rsp.result;
  endfunction

  // Reads only the value-source fields of the candidate.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [63:0] arriving_value(
      input forward_candidate_t c);
  /* verilator lint_on UNUSEDSIGNAL */
    if (c.reply) return '0;
    if (c.rsp_value)
      return CPU_602 ? {32'd0, (c.fctiwz ? arith_rsp.result[31:0] :
          reply_raw[31:0])} : arith_rsp.result;
    if (c.load_value) return c.load_single ? load_single : load_double;
    return c.fpr_value;
  endfunction

  // `value` is the stored-format result (see format_reply).
  function automatic ppc_fpu_result_t numeric_result(
      input ppc_fpu_result_t base, input arith_flags_t ar,
      input logic [63:0] value,
      input ppc_fpu_op_t op, input logic rc, input logic [2:0] cr_field,
      input logic fe0, input logic fe1, input logic [31:0] old_f
  );
    ppc_fpu_result_t out;
    logic [31:0] next_f;
    begin
      out = base;
      next_f = flags_fpscr(old_f, ar);
      if (flags_trap(ar, old_f)) begin
        out.exception = FPU_EMULATION_TRAP;
        out.fpr_write = 1'b0;
        out.fpscr_write = 1'b0;
        out.cr_write = 1'b0;
      end else begin
        out.fpr_write = ar.write_result;
        out.fpr_value = value;
        out.fpr_sp = CPU_602 && op != FP_FCTIWZ;
        out.fpr_lt = CPU_602 && op == FP_FCTIWZ;
        out.fpscr_write = 1'b1;
        out.fpscr_value = next_f;
        out.cr_write = ar.compare_valid ||
            (!ar.compare_valid && rc);
        out.cr_field = ar.compare_valid ? cr_field : 3'd1;
        out.cr_value = ar.compare_valid ? ar.fpcc : next_f[31:28];
        if (!CPU_602 && (fe0 || fe1) && next_f[30])
          out.exception = FPU_FP_ENABLED;
      end
      return out;
    end
  endfunction

  function automatic pending_t new_entry(input pending_t old,
                                         input ppc_fpu_issue_t is,
                                         input decoded_t d,
                                         input logic [4:0] first_src,
                                         input logic [31:0] ea);
    pending_t e;
    e = old;
    e.issue = is;
    e.decoded = d;
    e.src_a = first_src;
    e.dest_fpr = writes_fpr(d.kind, d.op, d.mem_load);
    e.ea = ea;
    return e;
  endfunction

  function automatic pending_t dispatched(input pending_t e);
    pending_t o;
    o = e;
    o.valid = 1'b1;
    o.started = 1'b0;
    o.done = 1'b0;
    o.finishing = 1'b0;
    o.arith_done = 1'b0;
    o.fpr_forwarded = 1'b0;
    o.cr_forwarded = 1'b0;
    o.local_wait = '0;
    o.mem_write = 1'b0;
    o.store_fill = 1'b0;
    return o;
  endfunction

  /* verilator lint_off UNUSEDSIGNAL */
  // Full result view of a pending entry.
  function automatic ppc_fpu_result_t entry_result(input pending_t p);
    ppc_fpu_result_t r;
    logic spr_read;
    begin
      spr_read = CPU_602 && p.decoded.kind == DK_MFSPR;
      r.tag = p.issue.tag;
      r.exception = p.st.exception;
      r.ea = p.ea;
      r.fault_code = p.st.fault_code;
      r.fault_info = p.st.exception == FPU_MEMORY_FAULT ? p.value[31:0] : '0;
      r.fpr_index = p.issue.insn[25:21];
      r.fpr_write = p.st.fpr_write;
      r.fpr_value = p.st.fpr_write ? p.value : '0;
      r.fpr_sp = p.st.fpr_sp;
      r.fpr_lt = p.st.fpr_lt;
      r.fpscr_write = p.st.fpscr_write;
      r.fpscr_value = p.st.fpscr_write ? p.value[31:0] : '0;
      r.cr_write = p.st.cr_write;
      r.cr_field = p.st.cr_field;
      r.cr_value = p.st.cr_value;
      r.gpr_update = p.st.gpr_update;
      r.gpr_index = spr_read ? p.issue.insn[25:21] : p.issue.insn[20:16];
      r.gpr_value = spr_read ? p.value[31:0] : p.ea;
      r.store = p.st.store;
      return r;
    end
  endfunction

  function automatic status_t status_of(input ppc_fpu_result_t r);
    status_t st;
    st.exception = r.exception;
    st.fault_code = r.fault_code;
    st.fpr_write = r.fpr_write;
    st.fpr_sp = r.fpr_sp;
    st.fpr_lt = r.fpr_lt;
    st.fpscr_write = r.fpscr_write;
    st.cr_write = r.cr_write;
    st.cr_field = r.cr_field;
    st.cr_value = r.cr_value;
    st.gpr_update = r.gpr_update;
    st.store = r.store;
    return st;
  endfunction

  // The one data word a result keeps.
  function automatic logic [63:0] value_of(input decode_kind_t kind,
                                           input ppc_fpu_result_t r);
    if (r.exception == FPU_MEMORY_FAULT) return {32'd0, r.fault_info};
    if (kind == DK_MTFS || kind == DK_MCRFS) return {32'd0, r.fpscr_value};
    if (CPU_602 && kind == DK_MFSPR) return {32'd0, r.gpr_value};
    return r.fpr_value;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  // D- and X-form FP loads and stores; RA is a GPR, so the first FPR
  // lookup reads frS instead.
  function automatic logic memory_form(input logic [5:0] primary);
    return primary[5:3] == 3'b110 || primary == 6'd31;
  endfunction

  // Selector class of a register after this cycle's writes.
  function automatic logic class_now(input logic [4:0] reg_index,
                                     input logic read_class);
    if (fpr_we[1] && fpr_waddr[1] == reg_index) return fpr_wdata[1][FPR_BITS];
    if (fpr_we[0] && fpr_waddr[0] == reg_index) return fpr_wdata[0][FPR_BITS];
    return read_class;
  endfunction

  // fsel takes frB when frA is a NaN or less than zero.
  function automatic logic selects_b(input logic [63:0] v);
    return CPU_602 ?
        (((v[30:23] == 8'hff) && v[22:0] != 23'd0) ||
         (v[31] && v[30:0] != 31'd0)) :
        (((v[62:52] == 11'h7ff) && v[51:0] != 52'd0) ||
         (v[63] && v[62:0] != 63'd0));
  endfunction

  // Youngest pending writer of a register: the producer a dispatching
  // instruction binds to.
  function automatic logic [PENDING_DEPTH-1:0] writer_of(
      input logic [4:0] reg_index);
    logic [PENDING_DEPTH-1:0] match;
    for (integer i = 0; i < PENDING_DEPTH; i++)
      match[i] = pending_q[i].valid && pending_q[i].dest_fpr &&
          pending_q[i].issue.insn[25:21] == reg_index;
    return youngest_of(match);
  endfunction

  // A bound producer supplies the operand; otherwise the register file
  // does. Per-slot values and readiness are shared by all lookups
  // (slot_src). Value bits of a source that is not ready are unused.
  function automatic source_t read_source(input logic [4:0] reg_index,
                                          input logic [FPR_BITS:0] stored,
                                          input logic [PENDING_DEPTH-1:0] producer);
    source_t s;
    begin
      s = '0;
      if (|producer) begin
        for (integer i = 0; i < PENDING_DEPTH; i++)
          if (producer[i]) s |= slot_src[i];
      end else begin
        s.ready = 1'b1;
        s.raw = {{(64-FPR_BITS){1'b0}}, stored[FPR_BITS-1:0]};
        s.sp = CPU_602 && sp_q[31-reg_index];
        s.lt = CPU_602 && lt_q[31-reg_index];
        s.selb = stored[FPR_BITS];
      end
      return s;
    end
  endfunction

  // MOVE/FSEL execute from captured operands in the second local pipeline
  // stage.  This keeps the backend finish bypass out of the FSEL data mux.
  function automatic ppc_fpu_result_t finish_local_data(
      input ppc_fpu_result_t base, input logic [1:0] move_kind,
      input logic is_move, input logic rc, input local_operand_t a,
      input local_operand_t b, input local_operand_t c,
      input logic c_lt);
    ppc_fpu_result_t r;
    logic choose_b;
    begin
      r = base;
      choose_b = CPU_602 ?
          (((a.raw[30:23] == 8'hff) && a.raw[22:0] != 23'd0) ||
           (a.raw[31] && a.raw[30:0] != 31'd0)) :
          (((a.raw[62:52] == 11'h7ff) && a.raw[51:0] != 52'd0) ||
           (a.raw[63] && a.raw[62:0] != 63'd0));
      if (r.exception == FPU_NO_EXCEPTION) begin
        if (is_move) begin
          r.fpr_write = 1'b1;
          r.fpr_sp = CPU_602;
          r.fpr_value = b.raw;
          if (CPU_602) begin
            case (move_kind)
              2'd1: r.fpr_value[31] = ~b.raw[31];
              2'd2: r.fpr_value[31] = 1'b1;
              2'd3: r.fpr_value[31] = 1'b0;
              default: ;
            endcase
            if (!b.sp) begin
              r.exception = FPU_EMULATION_TRAP;
              r.fpr_write = 1'b0;
            end
          end else begin
            case (move_kind)
              2'd1: r.fpr_value[63] = ~b.raw[63];
              2'd2: r.fpr_value[63] = 1'b1;
              2'd3: r.fpr_value[63] = 1'b0;
              default: ;
            endcase
          end
        end else begin
          r.fpr_write = 1'b1;
          r.fpr_value = choose_b ? b.raw : c.raw;
          r.fpr_sp = CPU_602;
          if (CPU_602 && (!a.sp || (choose_b && !b.sp) ||
                          (!choose_b && !c.sp))) begin
            r.exception = FPU_EMULATION_TRAP;
            r.fpr_write = 1'b0;
          end
          if (CPU_602 && !choose_b) case ({c.sp,c_lt})
            2'b10, 2'b11: ;
            default: begin
              r.exception = FPU_EMULATION_TRAP;
              r.fpr_write = 1'b0;
            end
          endcase
        end
        r.cr_write = rc && r.exception == FPU_NO_EXCEPTION;
        r.cr_field = 3'd1;
      end
      return r;
    end
  endfunction

  function automatic logic [31:0] status_change(input logic [31:0] old_f,
                                                  input logic [31:0] insn,
                                                  input logic [63:0] b);
    logic [31:0] n;
    begin
      n = old_f;
      case (insn[10:1])
        10'd38: if (insn[25:21] != 5'd1 && insn[25:21] != 5'd2) begin
          n[31-insn[25:21]] = 1'b1;
          if (!old_f[31-insn[25:21]] &&
              ((insn[25:21] >= 5'd3 && insn[25:21] <= 5'd12) ||
               (insn[25:21] >= 5'd21 && insn[25:21] <= 5'd23))) n[31] = 1'b1;
        end
        10'd70: if (insn[25:21] != 5'd1 && insn[25:21] != 5'd2)
          n[31-insn[25:21]] = 1'b0;
        10'd134: n[31-4*int'(insn[25:23]) -: 4] = insn[15:12];
        10'd711: for (integer i = 0; i < 8; i++)
          if (insn[24-i]) n[31-4*i -: 4] = b[31-4*i -: 4];
        10'd64: case (insn[20:18])
          3'd0: n[31:28] = 4'b0;
          3'd1: n[27:24] = 4'b0;
          3'd2: n[23:20] = 4'b0;
          3'd3: n[19] = 1'b0;
          3'd5: n[10:8] = 3'b0;
          default: n = old_f;
        endcase
        default: n = old_f;
      endcase
      return normalize_fpscr(n);
    end
  endfunction

  // Load data comes from load_single/load_double, formatted once.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic ppc_fpu_result_t memory_result(
      input ppc_fpu_result_t base, input logic mem_load,
      input logic mem_single, input ppc_fpu_mem_rsp_t reply
  );
    ppc_fpu_result_t r;
    begin
      r = base;
      r.tag = reply.tag;
      if (reply.fault) begin
        r.exception = FPU_MEMORY_FAULT;
        r.fault_code = reply.fault_code;
        r.fault_info = reply.fault_info;
        r.gpr_update = 1'b0;
        r.store = 1'b0;
      end else if (mem_load) begin
        r.fpr_write = 1'b1;
        r.fpr_value = mem_single ? load_single : load_double;
        r.fpr_sp = CPU_602;
        if (!mem_single && !load_fits) begin
          r.exception = FPU_EMULATION_TRAP;
          r.fpr_write = 1'b0;
          r.fpr_value = '0;
          r.gpr_update = 1'b0;
        end
      end
      return r;
    end
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  function automatic decode_info_t decode_packet(
      input logic [6:0] insn_hi, input logic [22:0] insn_lo,
      input logic [31:0] gpr_a,
      input logic [31:0] gpr_b
  );
    decode_info_t info;
    logic [31:0] spr;
    begin
    // Decode ignores BF bits 24:23; consumers retain the original word.
    info.decoded = '0;
    info.decoded.kind = DK_ILLEGAL;
    info.ea = 32'd0;
    spr = {22'd0, insn_lo[15:11], insn_lo[20:16]};
    if (insn_hi[6:1] >= 6'd48 && insn_hi[6:1] <= 6'd55) begin
      info.decoded.kind = DK_MEMORY;
      info.decoded.mem_load = (insn_hi[6:1] <= 6'd51);
      info.decoded.mem_store = !info.decoded.mem_load;
      info.decoded.mem_single = (insn_hi[6:1] == 6'd48) ||
                           (insn_hi[6:1] == 6'd49) ||
                           (insn_hi[6:1] == 6'd52) ||
                           (insn_hi[6:1] == 6'd53);
      info.decoded.mem_update = insn_hi[1];
      info.ea = (insn_lo[20:16] == 5'd0 ? 32'd0 : gpr_a) +
                 {{16{insn_lo[15]}}, insn_lo[15:0]};
    end else if (insn_hi[6:1] == 6'd31 && insn_lo[0] == 1'b0) begin
      info.decoded.kind = DK_MEMORY;
      info.ea = (insn_lo[20:16] == 5'd0 ? 32'd0 : gpr_a) + gpr_b;
      case (insn_lo[10:1])
        10'd535, 10'd567: begin info.decoded.mem_load=1'b1; info.decoded.mem_single=1'b1; info.decoded.mem_update=(insn_lo[10:1]==10'd567); end
        10'd599, 10'd631: begin info.decoded.mem_load=1'b1; info.decoded.mem_update=(insn_lo[10:1]==10'd631); end
        10'd663, 10'd695: begin info.decoded.mem_store=1'b1; info.decoded.mem_single=1'b1; info.decoded.mem_update=(insn_lo[10:1]==10'd695); end
        10'd727, 10'd759: begin info.decoded.mem_store=1'b1; info.decoded.mem_update=(insn_lo[10:1]==10'd759); end
        10'd983: begin info.decoded.mem_store=1'b1; info.decoded.mem_integer=1'b1; end
        10'd339, 10'd467: if (CPU_602 &&
            (spr == 32'd1021 || spr == 32'd1022)) begin
          info.decoded.kind = insn_lo[10:1] == 10'd339 ? DK_MFSPR : DK_MTSPR;
          info.decoded.spr_sp = spr == 32'd1021;
        end else info.decoded.kind = DK_ILLEGAL;
        default: info.decoded.kind=DK_ILLEGAL;
      endcase
    end else if (insn_hi[6:1] == 6'd59 || insn_hi[6:1] == 6'd63) begin
      info.decoded.kind = DK_ARITH;
      case (insn_hi[6:1])
        6'd59: begin
          info.decoded.single_result = 1'b1;
          case (insn_lo[5:1])
            5'd18: info.decoded.op=FP_DIV;
            5'd20: info.decoded.op=FP_SUB;
            5'd21: info.decoded.op=FP_ADD;
            5'd24: info.decoded.op=FP_FRES;
            5'd25: info.decoded.op=FP_MUL;
            5'd28: info.decoded.op=FP_MSUB;
            5'd29: info.decoded.op=FP_MADD;
            5'd30: info.decoded.op=FP_NMSUB;
            5'd31: info.decoded.op=FP_NMADD;
            default: info.decoded.kind=DK_ILLEGAL;
          endcase
        end
        default: begin
          case (insn_lo[10:1])
            10'd0: info.decoded.op=FP_CMPU;
            10'd12: info.decoded.op=FP_FRSP;
            10'd14: info.decoded.op=FP_FCTIW;
            10'd15: info.decoded.op=FP_FCTIWZ;
            10'd32: info.decoded.op=FP_CMPO;
            10'd38,10'd70,10'd134,10'd711: info.decoded.kind=DK_MTFS;
            10'd64: info.decoded.kind=DK_MCRFS;
            10'd583: info.decoded.kind=DK_MFFS;
            10'd40,10'd72,10'd136,10'd264: begin
              info.decoded.kind=DK_MOVE;
              case (insn_lo[10:1])
                10'd40: info.decoded.move_kind=2'd1;
                10'd136: info.decoded.move_kind=2'd2;
                10'd264: info.decoded.move_kind=2'd3;
                default: info.decoded.move_kind=2'd0;
              endcase
            end
            default: begin
              case (insn_lo[5:1])
                5'd18: info.decoded.op=FP_DIV;
                5'd20: info.decoded.op=FP_SUB;
                5'd21: info.decoded.op=FP_ADD;
                5'd23: info.decoded.kind=DK_FSEL;
                5'd25: info.decoded.op=FP_MUL;
                5'd26: info.decoded.op=FP_FRSQRTE;
                5'd28: info.decoded.op=FP_MSUB;
                5'd29: info.decoded.op=FP_MADD;
                5'd30: info.decoded.op=FP_NMSUB;
                5'd31: info.decoded.op=FP_NMADD;
                default: info.decoded.kind=DK_ILLEGAL;
              endcase
            end
          endcase
        end
      endcase
      if (info.decoded.kind == DK_ARITH) begin
        if ((info.decoded.op == FP_ADD || info.decoded.op == FP_SUB || info.decoded.op == FP_DIV) &&
            insn_lo[10:6] != 5'd0) info.decoded.kind=DK_ILLEGAL;
        if (info.decoded.op == FP_MUL && insn_lo[15:11] != 5'd0) info.decoded.kind=DK_ILLEGAL;
        if ((info.decoded.op == FP_FRES || info.decoded.op == FP_FRSQRTE ||
             info.decoded.op == FP_FRSP || info.decoded.op == FP_FCTIW ||
             info.decoded.op == FP_FCTIWZ) &&
            (insn_lo[20:16] != 5'd0 || insn_lo[10:6] != 5'd0)) info.decoded.kind=DK_ILLEGAL;
        if ((info.decoded.op == FP_CMPU || info.decoded.op == FP_CMPO) &&
            (insn_lo[22:21] != 2'b00 || insn_lo[0]))
          info.decoded.kind=DK_ILLEGAL;
      end
    end
    if (info.decoded.kind == DK_MOVE && insn_lo[20:16] != 5'd0)
      info.decoded.kind = DK_ILLEGAL;
    if (info.decoded.kind == DK_MFFS && insn_lo[20:11] != 10'd0)
      info.decoded.kind = DK_ILLEGAL;
    if (info.decoded.kind == DK_MCRFS &&
        (insn_lo[22:21] != 2'b00 || insn_lo[17:11] != 7'd0 || insn_lo[0]))
      info.decoded.kind = DK_ILLEGAL;
    if (info.decoded.kind == DK_MTFS) begin
      case (insn_lo[10:1])
        10'd38, 10'd70: if (insn_lo[20:11] != 10'd0) info.decoded.kind=DK_ILLEGAL;
        10'd134: if (insn_lo[22:16] != 7'd0 || insn_lo[11])
                    info.decoded.kind=DK_ILLEGAL;
        10'd711: if (insn_hi[0] || insn_lo[16]) info.decoded.kind=DK_ILLEGAL;
        default: info.decoded.kind=DK_ILLEGAL;
      endcase
    end
    if (info.decoded.kind == DK_MEMORY && info.decoded.mem_update && insn_lo[20:16] == 5'd0)
      info.decoded.kind = DK_ILLEGAL;
      return info;
    end
  endfunction

  always_comb begin
    pv[0] = pending_q[head_q];
    pv[1] = pending_q[head1_q];
  end

  // Operand view of each pending destination: its stored result, the
  // finishing arithmetic value (taken at the operand registers), the
  // registered arithmetic reply, or an arriving load.
  always_comb begin
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      slot_src[i] = '0;
      slot_src[i].raw = pending_q[i].value;
      slot_src[i].sp = pending_q[i].st.fpr_sp;
      slot_src[i].lt = pending_q[i].st.fpr_lt;
      if ((pending_q[i].done || pending_q[i].local_wait == 2'd1) &&
          pending_q[i].st.fpr_write &&
          pending_q[i].st.exception == FPU_NO_EXCEPTION) begin
        slot_src[i].ready = 1'b1;
      end else if (pending_q[i].finishing) begin
        // A trapping value aborts every younger consumer before it
        // commits, so only stores wait on the trap check. Only readiness
        // waits for the finishing write; a consumer launches only when
        // ready.
        slot_src[i].ready = arith_finish_write;
        slot_src[i].fwd = 1'b1;
        slot_src[i].raw = '0;
        slot_src[i].sp = CPU_602 && pending_q[i].decoded.op != FP_FCTIWZ;
        slot_src[i].lt = CPU_602 && pending_q[i].decoded.op == FP_FCTIWZ;
      // A flush blocks every launch, so the operand view ignores it.
      end else if (arith_rsp_held && arith_rsp.tag == pending_q[i].issue.tag &&
                   !flags_trap(flags_of(arith_rsp), fpscr_q) &&
                   arith_rsp.write_result) begin
        slot_src[i].ready = 1'b1;
        slot_src[i].raw = format_reply(pending_q[i].decoded.op);
        slot_src[i].sp = CPU_602 && pending_q[i].decoded.op != FP_FCTIWZ;
        slot_src[i].lt = CPU_602 && pending_q[i].decoded.op == FP_FCTIWZ;
      end else if (mem_rsp_match && mem_rsp_slot == PENDING_IDX_BITS'(i) &&
                   mem_rsp_i.tag == pending_q[i].issue.tag &&
                   pending_q[i].decoded.kind == DK_MEMORY &&
                   pending_q[i].decoded.mem_load && !mem_rsp_i.fault) begin
        slot_src[i].ready = pending_q[i].decoded.mem_single || load_fits;
        slot_src[i].raw = pending_q[i].decoded.mem_single ? load_single :
            load_double;
        slot_src[i].sp = CPU_602;
        slot_src[i].lt = 1'b0;
      end
      slot_src[i].selb = selects_b(slot_src[i].raw);
    end
  end

  // Source registers of each presented lane and their youngest pending
  // writers, independent of which work context takes the lane.
  always_comb begin
    for (integer l = 0; l < 2; l++) begin
      logic [31:6] insn;
      insn = l == 0 ? issue_i.insn[31:6] : issue1_i.insn[31:6];
      lane_index[l][0] = memory_form(insn[31:26]) ? insn[25:21] : insn[20:16];
      lane_index[l][1] = insn[15:11];
      lane_index[l][2] = insn[10:6];
      for (integer k = 0; k < 3; k++)
        lane_writer[l][k] = writer_of(lane_index[l][k]);
    end
  end

  always_comb begin
    decode0 = decode_packet(issue_i.insn[31:25],issue_i.insn[22:0],
                            issue_i.gpr_a,issue_i.gpr_b);
    decode1 = decode_packet(issue1_i.insn[31:25],issue1_i.insn[22:0],
                            issue1_i.gpr_a,issue1_i.gpr_b);
    decoded = decode0.decoded;
    issue_ea = decode0.ea;
    decoded1 = decode1.decoded;
    issue1_ea = decode1.ea;
  end

  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni) begin
      logic [PENDING_DEPTH-1:0] wait_fpu, wait_mem, wait_other;
      for (integer i = 0; i < PENDING_DEPTH; i++) begin
        wait_fpu[i] = pending_q[i].valid && !pending_q[i].started &&
            is_fpu_exec(pending_q[i].decoded.kind);
        wait_mem[i] = pending_q[i].valid && !pending_q[i].started &&
            pending_q[i].decoded.kind == DK_MEMORY;
        wait_other[i] = pending_q[i].valid && !pending_q[i].started &&
            !is_fpu_exec(pending_q[i].decoded.kind) &&
            pending_q[i].decoded.kind != DK_MEMORY;
      end
      assert ($countones(wait_fpu) <= 1 && $countones(wait_mem) <= 1 &&
              (wait_other == '0 || (wait_fpu == '0 && wait_mem == '0 &&
                                    $countones(wait_other) == 1)))
        else $error("more than one waiting entry per resource");
      for (integer i = 0; i < PENDING_DEPTH; i++)
        if (pending_q[i].valid && pending_q[i].finishing &&
            !(kill_all_i || safe_abort_flush || deferred_abort_flush))
          assert (arith_finish_valid &&
                  arith_finish.tag == pending_q[i].issue.tag)
            else $error("finishing slot without its reply");
      if (CPU_602 && arith_rsp_match && arith_rsp.write_result &&
          pending_q[arith_rsp_slot].decoded.op != FP_FCTIWZ &&
          !flags_trap(flags_of(arith_rsp), fpscr_q))
        assert (word_602(arith_rsp.result) == narrow_single(arith_rsp.result))
          else $error("written 602 result is a binary32 denormal %h",
                      arith_rsp.result);
    end
  end
  // synthesis translate_on

  // One waiting reservation entry is permitted. Ready independent operands
  // bypass it and enter the arithmetic pipe on the dispatch handshake.
  // Oldest-first picks run on physical slots; an age compare that depends
  // only on the registered head replaces the rotated scan.
  always_comb begin
    logic [PENDING_DEPTH-1:0] unstarted;
    logic [PENDING_DEPTH-1:0] exec_sel;
    logic [PENDING_DEPTH-1:0] second_sel;
    logic exec_is_mem, exec_is_fpu;
    for (integer i = 0; i < PENDING_DEPTH; i++)
      unstarted[i] = pending_q[i].valid && !pending_q[i].started;
    exec_sel = oldest_of(unstarted);
    exec_found = |unstarted;
    exec_slot = '0;
    exec_is_mem = 1'b0;
    exec_is_fpu = 1'b0;
    for (integer i = 0; i < PENDING_DEPTH; i++)
      if (exec_sel[i]) begin
        exec_slot |= PENDING_IDX_BITS'(i);
        exec_is_mem |= pending_q[i].decoded.kind == DK_MEMORY;
        exec_is_fpu |= is_fpu_exec(pending_q[i].decoded.kind);
      end
    // Dispatch admits at most one waiting entry per resource, and any other
    // kind waits alone, so the pair partner is the waiting entry with an
    // older waiting one; it forms beside the oldest pick.
    second_sel = '0;
    for (integer s = 0; s < PENDING_DEPTH; s++)
      for (integer t = 0; t < PENDING_DEPTH; t++)
        if (t != s && unstarted[t] && older_q[t][s] && unstarted[s])
          second_sel[s] = 1'b1;
    exec_pick = exec_sel;
    second_pick = second_sel;
    // The work contexts read their entries through the one-hot picks.
    exec_entry = '0;
    second_entry = '0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (exec_sel[i]) exec_entry |= pending_q[i];
      if (second_sel[i]) second_entry |= pending_q[i];
    end
    second_exec_found = |second_sel;
    second_exec_slot = '0;
    for (integer i = 0; i < PENDING_DEPTH; i++)
      if (second_sel[i]) second_exec_slot |= PENDING_IDX_BITS'(i);
    exec_kind_mem = exec_is_mem;
    exec_kind_fpu = exec_is_fpu;
    barrier_present = barrier_q;
    duplicate_tag = 1'b0;
    duplicate1_tag = 1'b0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (pending_q[i].valid) begin
        if (pending_q[i].issue.tag == issue_i.tag) duplicate_tag = 1'b1;
        if (pending_q[i].issue.tag == issue1_i.tag) duplicate1_tag = 1'b1;
      end
    end
  end

  always_comb begin
    arith_rsp_match = 1'b0;
    mem_rsp_match = 1'b0;
    arith_rsp_slot = '0;
    mem_rsp_slot = '0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (pending_q[i].valid) begin
        if (arith_rsp_valid && pending_q[i].started &&
            pending_q[i].decoded.kind == DK_ARITH &&
            pending_q[i].issue.tag == arith_rsp.tag) begin
          arith_rsp_match = 1'b1;
          arith_rsp_slot = PENDING_IDX_BITS'(i);
        end
        if (mem_rsp_valid_i && pending_q[i].started &&
            pending_q[i].decoded.kind == DK_MEMORY &&
            pending_q[i].issue.tag == mem_rsp_i.tag) begin
          mem_rsp_match = 1'b1;
          mem_rsp_slot = PENDING_IDX_BITS'(i);
        end
      end
    end
    arith_rsp_head = arith_rsp_match && arith_rsp_slot == head_q;
    mem_rsp_head = mem_rsp_match && mem_rsp_slot == head_q;
    mem_rsp_second = mem_rsp_match && mem_rsp_slot == head1_q;
  end

  always_comb begin
    logic [PENDING_DEPTH-1:0] inflight;
    abort_hit = '0;
    abort_index = '0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      abort_hit[i] = pending_q[i].valid && pending_q[i].issue.tag == abort_tag_i;
      inflight[i] = pending_q[i].valid &&
          pending_q[i].decoded.kind == DK_ARITH &&
          pending_q[i].started && !pending_q[i].arith_done &&
          !pending_q[i].done;
      if (abort_hit[i]) abort_index = age_of(head_q, PENDING_IDX_BITS'(i));
    end
    abort_index_valid = |abort_hit;
    // The matched entry and every younger one.
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      aborted[i] = 1'b0;
      for (integer t = 0; t < PENDING_DEPTH; t++)
        if (abort_hit[t] && (t == i || older_q[t][i])) aborted[i] = 1'b1;
    end
    safe_abort_flush = abort_valid_i && abort_index_valid;
    for (integer i = 0; i < PENDING_DEPTH; i++)
      for (integer t = 0; t < PENDING_DEPTH; t++)
        if (abort_hit[t] && older_q[i][t] && inflight[i])
          safe_abort_flush = 1'b0;
    older_arith_pending = |inflight;
    deferred_abort_flush = deferred_abort_flush_q && !older_arith_pending;
  end

  always_comb begin
    ppc_fpu_result_t head_base;
    head_result = '0;
    head_base = entry_result(pv[0]);
    head_available = pending_count_q != 3'd0 && pv[0].valid;
    if (head_available) begin
      head_result = head_base;
      if ((pv[0].decoded.kind == DK_MOVE ||
           pv[0].decoded.kind == DK_FSEL) && head_result.cr_write)
        head_result.cr_value = fpscr_q[31:28];
      if (pv[0].decoded.kind == DK_ARITH) begin
        if (pv[0].arith_done || arith_rsp_head)
          head_result = numeric_result(head_base,
              pv[0].arith_done ? pv[0].arith : flags_of(arith_rsp),
              pv[0].arith_done ? pv[0].value : format_reply(pv[0].decoded.op),
              pv[0].decoded.op, pv[0].issue.insn[0],
              pv[0].issue.insn[25:23],
              pv[0].issue.msr_fe0, pv[0].issue.msr_fe1, fpscr_q);
      end else if (pv[0].decoded.kind == DK_MEMORY &&
                   mem_rsp_head) begin
        head_result = memory_result(head_base,
            pv[0].decoded.mem_load, pv[0].decoded.mem_single,
            mem_rsp_i);
      end
    end
    matching_abort = abort_index_valid;
    abort_match = abort_valid_i && matching_abort;
    result_valid_o = rst_ni && !kill_all_i && !abort_match &&
        head_available && (pv[0].done ||
          (pv[0].local_wait == 2'd1 && spr_transfer(pv[0].decoded.kind)) ||
          (pv[0].decoded.kind == DK_ARITH &&
           arith_rsp_head) ||
          (pv[0].decoded.kind == DK_MEMORY &&
           mem_rsp_head));
    result_o = head_result;
    second_result = '0;
    if (pending_count_q > 3'd1 && pv[1].valid) begin
      second_result = entry_result(pv[1]);
      if (pv[1].decoded.kind == DK_MEMORY &&
          mem_rsp_second)
        second_result = memory_result(entry_result(pv[1]),
            pv[1].decoded.mem_load,
            pv[1].decoded.mem_single, mem_rsp_i);
    end
    result1_valid_o = !CPU_602 && result_valid_o &&
        pending_count_q > 3'd1 && pv[1].valid &&
        pv[1].decoded.kind == DK_MEMORY &&
        pv[1].decoded.mem_load &&
        (pv[1].done ||
         (mem_rsp_second)) &&
        head_result.exception == FPU_NO_EXCEPTION &&
        !head_result.fpr_write &&
        second_result.exception == FPU_NO_EXCEPTION &&
        second_result.fpr_write;
    result1_o = second_result;
    store_o = '0;
    if (pv[0].mem_write) begin
      store_o.tag = pv[0].issue.tag;
      store_o.ea = pv[0].ea;
      store_o.size_bytes = (pv[0].decoded.mem_single ||
                            pv[0].decoded.mem_integer) ? 4'd4 : 4'd8;
      store_o.write = 1'b1;
      store_o.data = store_data(pv[0].decoded.mem_integer,
          pv[0].decoded.mem_single,
          pv[0].store_fill ? reply_raw : pv[0].value);
    end
  end

  // Commit and issue handshakes are separate processes: results never depend
  // on them, so an integrator may gate commit and issue on the result.
  always_comb begin
    commit_match = head_available && commit_valid_i &&
        commit_tag_i == pv[0].issue.tag;
    store_valid_o = result_valid_o && head_result.store && commit_match;
    commit_ready_o = result_valid_o && commit_match &&
        (!head_result.store || store_ready_i);
    retire_fire = commit_ready_o;
    commit1_ready_o = result1_valid_o && retire_fire &&
        commit1_valid_i && commit1_tag_i == pv[1].issue.tag;
    retire1_fire = commit1_ready_o;
    retire_count = {1'b0,retire_fire} + {1'b0,retire1_fire};
    after_retire_count = pending_count_q - {1'b0,retire_count};
  end

  // Issue readiness is a separate process: results never depend on the issue
  // handshake, so an integrator may gate issue on retirement.
  always_comb begin
    // State-only readiness is formed per decode class; the lane decode,
    // retirement credits and handshakes select it last.
    dec_exec = is_fpu_exec(decoded.kind);
    dec_mem = decoded.kind == DK_MEMORY;
    dec_write = writes_fpr(decoded.kind, decoded.op, decoded.mem_load);
    dec1_exec = is_fpu_exec(decoded1.kind);
    dec1_mem = decoded1.kind == DK_MEMORY;
    dec1_write = writes_fpr(decoded1.kind, decoded1.op, decoded1.mem_load);
    pair_ok = !second_exec_found;
    ready_if_mem = !exec_found ||
        (pair_ok && exec_kind_fpu);
    ready_if_exec = (!exec_found ||
        (pair_ok && exec_kind_mem)) && !div_busy;
    retire_credit = (retire_fire && pv[0].dest_fpr) ||
        (retire1_fire && pv[1].dest_fpr);
    retire_credit2 = retire_fire && pv[0].dest_fpr &&
        retire1_fire && pv[1].dest_fpr;
    space_ok = pending_count_q != 3'(PENDING_DEPTH) || retire_fire;
    space1_ok = pending_count_q < 3'(PENDING_DEPTH-1) ||
        (pending_count_q == 3'(PENDING_DEPTH-1) && retire_fire) ||
        retire1_fire;
    fpr_ok = !dec_write || fpr_count_q != 3'd4 || retire_credit;
    case ({1'b0, dec_write} + {1'b0, dec1_write})
      2'd0: fpr1_ok = 1'b1;
      2'd1: fpr1_ok = fpr_count_q < 3'd4 || retire_credit;
      default: fpr1_ok = fpr_count_q < 3'd3 ||
          (fpr_count_q == 3'd3 && retire_credit) || retire_credit2;
    endcase
    issue_ready_o = rst_ni && !kill_all_i && !abort_valid_i &&
        !barrier_present && !duplicate_tag &&
        (dec_mem ? ready_if_mem : dec_exec ? ready_if_exec : !exec_found) &&
        (!is_barrier(decoded.kind, decoded.op) || pending_count_q == 3'd0) &&
        space_ok && fpr_ok;
  end

  always_comb begin
    dispatch_fire = issue_valid_i && issue_ready_o;
    issue1_ready_o = dispatch_fire && !exec_found &&
        !kill_all_i && !abort_valid_i && !barrier_present &&
        !is_barrier(decoded.kind, decoded.op) &&
        !is_barrier(decoded1.kind, decoded1.op) &&
        issue1_i.tag != issue_i.tag && !duplicate1_tag &&
        ((dec_exec && dec1_mem) || (dec_mem && dec1_exec)) &&
        (!dec1_exec || !div_busy) && space1_ok && fpr1_ok;
    dispatch1_fire = issue1_valid_i && issue1_ready_o;
  end

  always_comb begin
    work_issue = '0;
    work_decoded = '0;
    work_ea = '0;
    work_valid = 1'b0;
    work_dispatch = 1'b0;
    if (exec_found) begin
      work_issue.tag = exec_entry.issue.tag;
      work_issue.insn = exec_entry.issue.insn;
      work_issue.msr_fp = exec_entry.issue.msr_fp;
      work_issue.msr_fe0 = exec_entry.issue.msr_fe0;
      work_issue.msr_fe1 = exec_entry.issue.msr_fe1;
      work_issue.msr_pr = exec_entry.issue.msr_pr;
      work_decoded = exec_entry.decoded;
      work_ea = exec_entry.ea;
      work_valid = 1'b1;
    end else if (issue_valid_i) begin
      work_issue.tag = issue_i.tag;
      work_issue.insn = issue_i.insn;
      work_issue.msr_fp = issue_i.msr_fp;
      work_issue.msr_fe0 = issue_i.msr_fe0;
      work_issue.msr_fe1 = issue_i.msr_fe1;
      work_issue.msr_pr = issue_i.msr_pr;
      work_decoded = decoded;
      work_ea = issue_ea;
      work_valid = 1'b1;
      work_dispatch = 1'b1;
    end
    work_admitted = !work_dispatch || dispatch_fire;
    // A memory form's first lookup reads the store source frS.
    src_a_index = exec_found ? exec_entry.src_a : lane_index[0][0];
    src_b_index = work_issue.insn[15:11];
    src_c_index = work_issue.insn[10:6];
    // A waiting entry reads its bound producers; a dispatching one binds
    // to the youngest pending writers.
    for (integer k = 0; k < 3; k++)
      bind0[k] = work_dispatch ? lane_writer[0][k] : exec_entry.producer[k];
    source_a = read_source(src_a_index, fpr_rdata[0], bind0[0]);
    // A waiting fsel's register-file selector class needs no read.
    if (!work_dispatch && ~|bind0[0]) source_a.selb = exec_entry.a_class;
    source_b = read_source(src_b_index, fpr_rdata[1], bind0[1]);
    source_c = read_source(src_c_index, fpr_rdata[2], bind0[2]);
    source_d = source_a;
    src_a = source_a.raw;
    src_b = source_b.raw;
    src_c = source_c.raw;
    // A finishing source is checked when the reply fills the entry.
    src_d_bad = !source_d.fwd && stfd_traps(source_d.raw[30:0]);
    store_d_ready = source_d.ready;
    src_a_sp = source_a.sp;
    src_b_sp = source_b.sp;
    src_c_sp = source_c.sp;
    src_d_sp = source_d.sp;
    src_b_lt = source_b.lt;
    src_d_lt = source_d.lt;
    use_a = 1'b0;
    use_b = 1'b0;
    use_c = 1'b0;
    use_d = 1'b0;
    select_b = source_a.selb;
    if (work_decoded.kind == DK_ARITH) begin
      use_a = !(work_decoded.op == FP_FRSP || work_decoded.op == FP_FCTIW ||
          work_decoded.op == FP_FCTIWZ || work_decoded.op == FP_FRES ||
          work_decoded.op == FP_FRSQRTE);
      use_b = work_decoded.op != FP_MUL;
      use_c = work_decoded.op == FP_MUL || work_decoded.op == FP_MADD ||
          work_decoded.op == FP_MSUB || work_decoded.op == FP_NMADD ||
          work_decoded.op == FP_NMSUB;
    end else if (work_decoded.kind == DK_MOVE || work_decoded.kind == DK_MTFS)
      use_b = work_decoded.kind == DK_MOVE || work_issue.insn[10:1] == 10'd711;
    else if (work_decoded.kind == DK_FSEL) begin
      // A forwarded selector is known only in the local stage.
      use_a = 1'b1;
      use_b = select_b || source_a.fwd;
      use_c = !select_b || source_a.fwd;
    end else if (work_decoded.kind == DK_MEMORY && work_decoded.mem_store)
      use_d = 1'b1;
    source_waiting = (use_a && !source_a.ready) ||
        (use_b && !source_b.ready) || (use_c && !source_c.ready) ||
        (use_d && !store_d_ready) ||
        (!is_fpu_exec(work_decoded.kind) &&
         ((use_a && source_a.fwd) || (use_b && source_b.fwd) ||
          (use_c && source_c.fwd)));
    sources_ready = !source_waiting;
    mem_sources_ready = !work_decoded.mem_store || store_d_ready;
    mem_tags_ok = !CPU_602 || !work_decoded.mem_store ||
        (work_decoded.mem_integer ? source_d.lt : source_d.sp);
    operand_tags_ok = 1'b1;
    if (CPU_602) begin
      if (work_decoded.kind == DK_ARITH) begin
        if (use_a) begin
          // SP and LT are independent; both 10 and 11 satisfy the SP gate.
          case ({src_a_sp,source_a.lt})
            2'b10,2'b11: ;
            default: operand_tags_ok = 1'b0;
          endcase
        end
        if (use_b && !src_b_sp) operand_tags_ok = 1'b0;
        if (use_c && !src_c_sp) operand_tags_ok = 1'b0;
      end
      if (work_decoded.kind == DK_MTFS && work_issue.insn[10:1] == 10'd711)
        operand_tags_ok = src_b_lt;
      if (work_decoded.kind == DK_MOVE) operand_tags_ok = src_b_sp;
      if (work_decoded.kind == DK_MEMORY && work_decoded.mem_store)
        operand_tags_ok = work_decoded.mem_integer ? src_d_lt : src_d_sp;
    end
  end

  // Resolve the second work context before the late dispatch-credit decision.
  // An old reservation uses it first; otherwise lane 0 or lane 1 is decoded
  // speculatively, but only an accepted lane can launch a resource request.
  // A lane-1 source bound to lane-0's new destination waits for its full tag.
  always_comb begin
    work1_issue = '0;
    work1_decoded = '0;
    work1_ea = '0;
    work1_valid = 1'b0;
    work1_old = 1'b0;
    if (second_exec_found) begin
      work1_issue.tag = second_entry.issue.tag;
      work1_issue.insn = second_entry.issue.insn;
      work1_issue.msr_fp = second_entry.issue.msr_fp;
      work1_decoded = second_entry.decoded;
      work1_ea = second_entry.ea;
      work1_valid = 1'b1;
      work1_old = 1'b1;
    end else if (exec_found && issue_valid_i) begin
      work1_issue.tag = issue_i.tag;
      work1_issue.insn = issue_i.insn;
      work1_issue.msr_fp = issue_i.msr_fp;
      work1_decoded = decoded;
      work1_ea = issue_ea;
      work1_valid = 1'b1;
    end else if (!exec_found && issue1_valid_i) begin
      work1_issue.tag = issue1_i.tag;
      work1_issue.insn = issue1_i.insn;
      work1_issue.msr_fp = issue1_i.msr_fp;
      work1_decoded = decoded1;
      work1_ea = issue1_ea;
      work1_valid = 1'b1;
    end
    work1_admitted = work1_old ||
        (exec_found ? dispatch_fire : dispatch1_fire);
    work1_index[0] = work1_old ? second_entry.src_a :
        lane_index[exec_found ? 0 : 1][0];
    work1_index[1] = work1_issue.insn[15:11];
    work1_index[2] = work1_issue.insn[10:6];
    for (integer k = 0; k < 3; k++)
      bind1[k] = work1_old ? second_entry.producer[k] :
          lane_writer[exec_found ? 0 : 1][k];
    work1_a = read_source(work1_index[0], fpr_rdata[3], bind1[0]);
    if (work1_old && ~|bind1[0]) work1_a.selb = second_entry.a_class;
    work1_b = read_source(work1_index[1], fpr_rdata[4], bind1[1]);
    work1_c = read_source(work1_index[2], fpr_rdata[5], bind1[2]);
    work1_d = work1_a;
    work1_d_bad = !work1_d.fwd && stfd_traps(work1_d.raw[30:0]);
    work1_store_d_ready = work1_d.ready;
    work1_select_b = work1_a.selb;
    work1_use_a = 1'b0;
    work1_use_b = 1'b0;
    work1_use_c = 1'b0;
    work1_use_d = 1'b0;
    if (work1_decoded.kind == DK_ARITH) begin
      work1_use_a = !(work1_decoded.op == FP_FRSP ||
          work1_decoded.op == FP_FCTIW || work1_decoded.op == FP_FCTIWZ ||
          work1_decoded.op == FP_FRES || work1_decoded.op == FP_FRSQRTE);
      work1_use_b = work1_decoded.op != FP_MUL;
      work1_use_c = work1_decoded.op == FP_MUL ||
          work1_decoded.op == FP_MADD || work1_decoded.op == FP_MSUB ||
          work1_decoded.op == FP_NMADD || work1_decoded.op == FP_NMSUB;
    end else if (work1_decoded.kind == DK_MOVE)
      work1_use_b = 1'b1;
    else if (work1_decoded.kind == DK_FSEL) begin
      work1_use_a = 1'b1;
      work1_use_b = work1_select_b || work1_a.fwd;
      work1_use_c = !work1_select_b || work1_a.fwd;
    end else if (work1_decoded.kind == DK_MEMORY && work1_decoded.mem_store)
      work1_use_d = 1'b1;
    work1_lane0_dep = !exec_found && issue_valid_i && issue1_valid_i &&
        writes_fpr(decoded.kind, decoded.op, decoded.mem_load) &&
        ((work1_use_a && issue_i.insn[25:21] == work1_issue.insn[20:16]) ||
         (work1_use_b && issue_i.insn[25:21] == work1_issue.insn[15:11]) ||
         (work1_use_c && issue_i.insn[25:21] == work1_issue.insn[10:6]) ||
         (work1_use_d && issue_i.insn[25:21] == work1_issue.insn[25:21]));
    work1_mem_lane0_dep = !exec_found && issue_valid_i && issue1_valid_i &&
        work1_decoded.kind == DK_MEMORY && work1_decoded.mem_store &&
        writes_fpr(decoded.kind, decoded.op, decoded.mem_load) &&
        issue_i.insn[25:21] == work1_issue.insn[25:21];
    work1_mem_sources_ready =
        (!work1_decoded.mem_store || work1_store_d_ready) &&
        !work1_mem_lane0_dep;
    work1_mem_tags_ok = !CPU_602 || !work1_decoded.mem_store ||
        (work1_decoded.mem_integer ? work1_d.lt : work1_d.sp);
    work1_sources_ready = !work1_decoded.spr_sp && !work1_lane0_dep &&
        (!work1_use_a || work1_a.ready) &&
        (!work1_use_b || work1_b.ready) &&
        (!work1_use_c || work1_c.ready) &&
        (!work1_use_d || work1_store_d_ready);
    work1_tags_ok = 1'b1;
    if (CPU_602) begin
      if (work1_decoded.kind == DK_ARITH) begin
        if (work1_use_a) case ({work1_a.sp,work1_a.lt})
          2'b10,2'b11: ;
          default: work1_tags_ok = 1'b0;
        endcase
        if (work1_use_b) case ({work1_b.sp,work1_b.lt})
          2'b10,2'b11: ;
          default: work1_tags_ok = 1'b0;
        endcase
        if (work1_use_c) case ({work1_c.sp,work1_c.lt})
          2'b10,2'b11: ;
          default: work1_tags_ok = 1'b0;
        endcase
      end
      if (work1_decoded.kind == DK_MOVE) case ({work1_b.sp,work1_b.lt})
        2'b10,2'b11: ;
        default: work1_tags_ok = 1'b0;
      endcase
      if (work1_decoded.kind == DK_MEMORY && work1_decoded.mem_store)
        work1_tags_ok = work1_decoded.mem_integer ?
            work1_d.lt : work1_d.sp;
    end
  end

  always_comb begin
    work1_arith_eligible = rst_ni && !kill_all_i && !abort_valid_i &&
        work1_valid && work1_sources_ready && work1_tags_ok &&
        work1_decoded.kind == DK_ARITH && work1_issue.msr_fp &&
        !(CPU_602 && (work1_decoded.op == FP_FCTIW ||
                      (work1_issue.insn[31:26] == 6'd63 &&
                       work1_decoded.op != FP_FCTIWZ &&
                       work1_decoded.op != FP_CMPU &&
                       work1_decoded.op != FP_CMPO &&
                       work1_decoded.op != FP_FRSP &&
                       work1_decoded.op != FP_FRSQRTE)));
    work1_mem_eligible = rst_ni && !kill_all_i && !abort_valid_i &&
        work1_valid && work1_mem_sources_ready && work1_mem_tags_ok &&
        work1_decoded.kind == DK_MEMORY && work1_issue.msr_fp &&
        (work1_ea[1:0] == 2'b00 ||
         (CPU_602 && work1_decoded.mem_load)) &&
        !(CPU_602 && work1_decoded.mem_store &&
          !work1_decoded.mem_single && !work1_decoded.mem_integer &&
          work1_d_bad && !work1_offer_held);
    work1_arith_launch = work1_arith_eligible &&
        !deferred_abort_flush_q && work1_admitted;
    work1_mem_launch = work1_mem_eligible && work1_admitted;
    work1_local_launch = rst_ni && !kill_all_i && !abort_valid_i &&
        work1_valid && work1_admitted &&
        (work1_decoded.kind == DK_MEMORY ?
         work1_mem_sources_ready : work1_sources_ready) &&
        !work1_arith_eligible && !work1_mem_eligible &&
        (!(work1_decoded.kind == DK_MOVE ||
           work1_decoded.kind == DK_FSEL) || arith_req_ready);
    work1_mem_req = '0;
    work1_mem_req.tag = work1_issue.tag;
    work1_mem_req.ea = work1_ea;
    work1_mem_req.size_bytes =
        (work1_decoded.mem_single || work1_decoded.mem_integer) ? 4'd4 : 4'd8;
    work1_mem_req.write = work1_decoded.mem_store;
    // Store data reaches the LSU only in the authorized store descriptor,
    // which converts the raw source register held in the entry. A source
    // finishing this cycle is filled from the reply next cycle.
    work1_mem_value = work1_decoded.mem_store ? work1_d.raw : '0;
    work1_mem_fill = work1_decoded.mem_store && work1_d.fwd;
    work1_fire = (work1_arith_launch && arith_req_ready) ||
        (work1_mem_launch && mem_req_ready_i) || work1_local_launch;
  end
  assign combined_arith_launch = arith_launch || work1_arith_launch;
  always_comb begin
    load_single = CPU_602 ? {32'd0, mem_rsp_i.data[31:0]} :
        widen_single(mem_rsp_i.data[31:0]);
    load_double = CPU_602 ? {32'd0, word_602(mem_rsp_i.data)} :
        mem_rsp_i.data;
    load_fits = !CPU_602 || fits_602(mem_rsp_i.data[62:0]);
  end
  // Only one context can launch arithmetic in a cycle, and a context
  // holding arithmetic excludes the other, so operands follow the kind.
  assign arith_from_work = work_decoded.kind == DK_ARITH;
  assign arith_req_fwd = arith_from_work ?
      {source_c.fwd, source_b.fwd, source_a.fwd} :
      {work1_c.fwd, work1_b.fwd, work1_a.fwd};

  always_comb begin
    logic [63:0] op_a, op_b, op_c;
    op_a = arith_from_work ? src_a : work1_a.raw;
    op_b = arith_from_work ? src_b : work1_b.raw;
    op_c = arith_from_work ? src_c : work1_c.raw;
    arith_req = '0;
    arith_req.tag = arith_from_work ? work_issue.tag : work1_issue.tag;
    arith_req.op = arith_from_work ? work_decoded.op : work1_decoded.op;
    arith_req.a = CPU_602 ? operand_602(op_a[31:0]) : op_a;
    arith_req.b = CPU_602 ? operand_602(op_b[31:0]) : op_b;
    arith_req.c = CPU_602 ? operand_602(op_c[31:0]) : op_c;
    arith_req.rn = fpscr_q[1:0];
    arith_req.ni = fpscr_q[2];
    arith_req.ve = fpscr_q[7];
    arith_req.oe = fpscr_q[6];
    arith_req.ue = fpscr_q[5];
    arith_req.ze = fpscr_q[4];
    arith_req.single_result = arith_from_work ?
        work_decoded.single_result : work1_decoded.single_result;
    arith_eligible = rst_ni && !kill_all_i && !abort_valid_i && work_valid &&
        sources_ready && operand_tags_ok && work_decoded.kind == DK_ARITH &&
        work_issue.msr_fp &&
        !(CPU_602 && (work_decoded.op == FP_FCTIW ||
                      (work_issue.insn[31:26] == 6'd63 &&
                       work_decoded.op != FP_FCTIWZ &&
                       work_decoded.op != FP_CMPU &&
                       work_decoded.op != FP_CMPO &&
                       work_decoded.op != FP_FRSP &&
                       work_decoded.op != FP_FRSQRTE)));
    mem_eligible = rst_ni && !kill_all_i && !abort_valid_i && work_valid &&
        mem_sources_ready && mem_tags_ok &&
        work_decoded.kind == DK_MEMORY &&
        work_issue.msr_fp && (work_ea[1:0] == 2'b00 ||
          (CPU_602 && work_decoded.mem_load)) &&
        !(CPU_602 && work_decoded.mem_store &&
          !work_decoded.mem_single && !work_decoded.mem_integer &&
          src_d_bad && !offer_held);
    arith_launch = arith_eligible && !deferred_abort_flush_q && work_admitted;
    mem_launch = mem_eligible && work_admitted;
    local_fpu_uses_pipe = work_decoded.kind == DK_MOVE ||
        work_decoded.kind == DK_FSEL || work_decoded.kind == DK_MFFS ||
        work_decoded.kind == DK_MCRFS || work_decoded.kind == DK_MTFS;
    local_launch = rst_ni && !kill_all_i && !abort_valid_i && work_valid &&
        work_admitted &&
        (work_decoded.kind == DK_MEMORY ? mem_sources_ready : sources_ready) &&
        !arith_eligible && !mem_eligible &&
        (!local_fpu_uses_pipe || arith_req_ready);
    arith_rsp_ready = 1'b1;
    // A same-cycle LSU reply waits until its request is registered.
    mem_rsp_ready_o = rst_ni && !kill_all_i &&
        !(work_valid && work_admitted &&
          work_decoded.kind == DK_MEMORY &&
          mem_rsp_i.tag == work_issue.tag) &&
        !(work1_valid && work1_admitted &&
          work1_decoded.kind == DK_MEMORY &&
          mem_rsp_i.tag == work1_issue.tag);
    mem_req_o = '0;
    mem_req_o.tag = work_issue.tag;
    mem_req_o.ea = work_ea;
    mem_req_o.size_bytes = (work_decoded.mem_single || work_decoded.mem_integer) ?
        4'd4 : 4'd8;
    mem_req_o.write = work_decoded.mem_store;
    mem_value = work_decoded.mem_store ? source_d.raw : '0;
    mem_fill = work_decoded.mem_store && source_d.fwd;
    if (work1_mem_launch) mem_req_o = work1_mem_req;
    mem_req_valid_o = mem_launch || work1_mem_launch;
    exec_fire = (arith_launch && arith_req_ready) ||
        (mem_launch && mem_req_ready_i) || local_launch;
  end

  ppc_fpu_arith #(.CPU_602(CPU_602)) arithmetic (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .req_valid_i(combined_arith_launch), .req_ready_o(arith_req_ready),
      .req_i(arith_req),
      .req_fwd_i(arith_req_fwd),
      .rsp_valid_o(arith_rsp_valid), .rsp_held_o(arith_rsp_held),
      .rsp_ready_i(arith_rsp_ready), .rsp_o(arith_rsp),
      .finish_valid_o(arith_finish_valid), .finish_o(arith_finish),
      .finish_write_o(arith_finish_write),
      .next_finish_valid_o(arith_next_finish_valid),
      .next_finish_tag_o(arith_next_finish_tag),
      .div_busy_o(div_busy),
      .flush_i(kill_all_i || safe_abort_flush || deferred_abort_flush)
  );

  always_comb begin
    exec_result = '0;
    exec_result.tag = work_issue.tag;
    exec_result.ea = work_ea;
    exec_result.fpr_index = work_issue.insn[25:21];
    exec_result.gpr_index = work_issue.insn[20:16];
    exec_result.gpr_value = work_ea;
    exec_result.gpr_update = work_decoded.kind == DK_MEMORY &&
        work_decoded.mem_update;
    exec_result.cr_field = work_issue.insn[25:23];
    proposed_fpscr = status_change(fpscr_q, work_issue.insn, src_b);
    if (work_decoded.kind == DK_ILLEGAL) begin
      exec_result.exception = FPU_ILLEGAL;
      exec_result.gpr_update = 1'b0;
    end else if ((work_decoded.kind == DK_MFSPR ||
                  work_decoded.kind == DK_MTSPR) && work_issue.msr_pr) begin
      exec_result.exception = FPU_PRIVILEGED;
      exec_result.gpr_update = 1'b0;
    end else if (!work_issue.msr_fp &&
                 work_decoded.kind != DK_MFSPR &&
                 work_decoded.kind != DK_MTSPR) begin
      exec_result.exception = FPU_UNAVAILABLE;
      exec_result.gpr_update = 1'b0;
    end else if (CPU_602 && work_decoded.kind == DK_ARITH &&
                 (work_decoded.op == FP_FCTIW ||
                  (work_issue.insn[31:26] == 6'd63 &&
                   work_decoded.op != FP_FCTIWZ &&
                   work_decoded.op != FP_CMPU &&
                   work_decoded.op != FP_CMPO &&
                   work_decoded.op != FP_FRSP &&
                   work_decoded.op != FP_FRSQRTE))) begin
      exec_result.exception = FPU_EMULATION_TRAP;
    end else if (!operand_tags_ok && work_decoded.kind != DK_MOVE &&
                 work_decoded.kind != DK_FSEL) begin
      exec_result.exception = CPU_602 ? FPU_EMULATION_TRAP : FPU_ILLEGAL;
      exec_result.gpr_update = 1'b0;
    end else begin
      case (work_decoded.kind)
        DK_MOVE, DK_FSEL: ;  // Operand data and tags resolve in stage two.
        DK_MFFS: begin
          exec_result.fpr_write = 1'b1;
          exec_result.fpr_value = {32'd0,fpscr_q};
          exec_result.fpr_lt = CPU_602;
          exec_result.cr_write = work_issue.insn[0];
          exec_result.cr_field = 3'd1;
          exec_result.cr_value = fpscr_q[31:28];
        end
        DK_MCRFS: begin
          exec_result.fpscr_write = 1'b1;
          exec_result.fpscr_value = proposed_fpscr;
          exec_result.cr_write = 1'b1;
          exec_result.cr_field = work_issue.insn[25:23];
          exec_result.cr_value =
              fpscr_q[31-4*int'(work_issue.insn[20:18]) -: 4];
        end
        DK_MTFS: begin
          exec_result.fpscr_write = 1'b1;
          exec_result.fpscr_value = proposed_fpscr;
          exec_result.cr_write = work_issue.insn[0];
          exec_result.cr_field = 3'd1;
          exec_result.cr_value = proposed_fpscr[31:28];
          if (!CPU_602 && (work_issue.msr_fe0 || work_issue.msr_fe1) &&
              proposed_fpscr[30]) exec_result.exception = FPU_FP_ENABLED;
          if (CPU_602 && proposed_fpscr[30] &&
              (work_issue.msr_fe0 || work_issue.msr_fe1))
            exec_result.exception = FPU_FP_ENABLED;
        end
        DK_MFSPR: begin
          exec_result.gpr_update = 1'b1;
          exec_result.gpr_index = work_issue.insn[25:21];
          exec_result.gpr_value = work_decoded.spr_sp ? sp_q : lt_q;
        end
        DK_MTSPR: begin
          exec_result.gpr_update = 1'b0;
        end
        DK_MEMORY: begin
          if (work_ea[1:0] != 2'b00 &&
              (!CPU_602 || work_decoded.mem_store)) begin
            exec_result.exception = FPU_ALIGNMENT;
            exec_result.gpr_update = 1'b0;
          end else if (CPU_602 && work_decoded.mem_store &&
                       !work_decoded.mem_single && !work_decoded.mem_integer &&
                       src_d_bad) begin
            exec_result.exception = FPU_EMULATION_TRAP;
            exec_result.gpr_update = 1'b0;
          end else exec_result.store = work_decoded.mem_store;
        end
        default: ;
      endcase
    end
  end

  always_comb begin
    work1_result = '0;
    work1_result.tag = work1_issue.tag;
    work1_result.ea = work1_ea;
    work1_result.fpr_index = work1_issue.insn[25:21];
    work1_result.gpr_index = work1_issue.insn[20:16];
    work1_result.gpr_value = work1_ea;
    work1_result.gpr_update = work1_decoded.kind == DK_MEMORY &&
        work1_decoded.mem_update;
    if (!work1_issue.msr_fp) begin
      work1_result.exception = FPU_UNAVAILABLE;
      work1_result.gpr_update = 1'b0;
    end else if (CPU_602 && work1_decoded.kind == DK_ARITH &&
                 (work1_decoded.op == FP_FCTIW ||
                  (work1_issue.insn[31:26] == 6'd63 &&
                   work1_decoded.op != FP_FCTIWZ &&
                   work1_decoded.op != FP_CMPU &&
                   work1_decoded.op != FP_CMPO &&
                   work1_decoded.op != FP_FRSP &&
                   work1_decoded.op != FP_FRSQRTE))) begin
      work1_result.exception = FPU_EMULATION_TRAP;
    end else if (!work1_tags_ok && work1_decoded.kind != DK_MOVE &&
                 work1_decoded.kind != DK_FSEL) begin
      work1_result.exception = FPU_EMULATION_TRAP;
      work1_result.gpr_update = 1'b0;
    end else begin
      case (work1_decoded.kind)
        DK_MOVE, DK_FSEL: ;  // Resolved from captured operands next stage.
        DK_MEMORY: begin
          if (work1_ea[1:0] != 2'b00 &&
              (!CPU_602 || work1_decoded.mem_store)) begin
            work1_result.exception = FPU_ALIGNMENT;
            work1_result.gpr_update = 1'b0;
          end else if (CPU_602 && work1_decoded.mem_store &&
                       !work1_decoded.mem_single &&
                       !work1_decoded.mem_integer &&
                       work1_d_bad) begin
            work1_result.exception = FPU_EMULATION_TRAP;
            work1_result.gpr_update = 1'b0;
          end else work1_result.store = work1_decoded.mem_store;
        end
        default: ;
      endcase
    end
  end

  // Launch records. Only stores and the serialized status and SPR reads
  // produce a value at launch, and a context holding one excludes a second
  // from the other context, so the value has one source.
  // Reads only the kind and store bit.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic valued_kind(input decoded_t d);
  /* verilator lint_on UNUSEDSIGNAL */
    return (d.kind == DK_MEMORY && d.mem_store) || d.kind == DK_MFFS ||
        d.kind == DK_MTFS || d.kind == DK_MCRFS ||
        (CPU_602 && d.kind == DK_MFSPR);
  endfunction

  always_comb begin
    launch_value = !valued_kind(work_decoded) ? work1_mem_value :
        work_decoded.kind == DK_MEMORY ? mem_value :
        value_of(work_decoded.kind, exec_result);
    launch0 = '0;
    launch0.record = local_launch || mem_launch;
    launch0.st = status_of(exec_result);
    launch0.local_wait = local_launch ? local_latency(work_decoded.kind) : 2'd0;
    launch0.mem_write = mem_launch && work_decoded.mem_store;
    launch0.store_fill = mem_launch && mem_fill;
    launch0.value_write = valued_kind(work_decoded);
    launch1 = '0;
    launch1.record = work1_local_launch || work1_mem_launch;
    launch1.st = status_of(work1_result);
    launch1.local_wait = work1_local_launch ?
        local_latency(work1_decoded.kind) : 2'd0;
    launch1.mem_write = work1_mem_launch && work1_decoded.mem_store;
    launch1.store_fill = work1_mem_launch && work1_mem_fill;
    launch1.value_write = valued_kind(work1_decoded);
  end

  // Launch sets only flags; the record's status and value are written
  // every cycle while the entry waits (see record_launch).
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic pending_t launched(input pending_t e, input launch_t l);
  /* verilator lint_on UNUSEDSIGNAL */
    pending_t o;
    o = e;
    o.started = 1'b1;
    if (l.record) begin
      o.local_wait = l.local_wait;
      o.mem_write = l.mem_write;
      o.store_fill = l.store_fill;
    end
    return o;
  endfunction

  // A waiting or free slot's status and value are unused until launch, so
  // its context's record is written without waiting for the launch
  // decision.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic pending_t record_launch(input pending_t e,
                                             input launch_t l);
  /* verilator lint_on UNUSEDSIGNAL */
    pending_t o;
    o = e;
    o.st = l.st;
    if (l.value_write) o.value = launch_value;
    return o;
  endfunction

  // Only one local FPU instruction can launch per edge, and a work context
  // holding a move or select excludes a second one. The operand registers
  // load from that context every cycle; only the valid bit waits for launch.
  always_comb begin
    logic work_local;
    work_local = work_decoded.kind == DK_MOVE || work_decoded.kind == DK_FSEL;
    local_stage_d.valid =
        (local_launch && work_local) ||
        (work1_local_launch && (work1_decoded.kind == DK_MOVE ||
                                work1_decoded.kind == DK_FSEL));
    if (work_local) begin
      local_stage_d.tag = work_issue.tag;
      local_stage_d.is_move = work_decoded.kind == DK_MOVE;
      local_stage_d.rc = work_issue.insn[0];
      local_stage_d.move_kind = work_decoded.move_kind;
      local_stage_d.a.raw = source_a.raw;
      local_stage_d.a.sp = source_a.sp;
      local_stage_d.b.raw = source_b.raw;
      local_stage_d.b.sp = source_b.sp;
      local_stage_d.c.raw = source_c.raw;
      local_stage_d.c.sp = source_c.sp;
      local_stage_d.c_lt = source_c.lt;
      local_stage_d.fwd = {source_c.fwd, source_b.fwd, source_a.fwd};
    end else begin
      local_stage_d.tag = work1_issue.tag;
      local_stage_d.is_move = work1_decoded.kind == DK_MOVE;
      local_stage_d.rc = work1_issue.insn[0];
      local_stage_d.move_kind = work1_decoded.move_kind;
      local_stage_d.a.raw = work1_a.raw;
      local_stage_d.a.sp = work1_a.sp;
      local_stage_d.b.raw = work1_b.raw;
      local_stage_d.b.sp = work1_b.sp;
      local_stage_d.c.raw = work1_c.raw;
      local_stage_d.c.sp = work1_c.sp;
      local_stage_d.c_lt = work1_c.lt;
      local_stage_d.fwd = {work1_c.fwd, work1_b.fwd, work1_a.fwd};
    end
  end

  assign reply_raw = CPU_602 ? {32'd0, word_602(arith_rsp.result)} :
      arith_rsp.result;

  // A local-stage operand forwarded last cycle is now the registered reply.
  always_comb begin
    local_a = local_stage_q.a;
    local_b = local_stage_q.b;
    local_c = local_stage_q.c;
    if (local_stage_q.fwd[0]) local_a.raw = reply_raw;
    if (local_stage_q.fwd[1]) local_b.raw = reply_raw;
    if (local_stage_q.fwd[2]) local_c.raw = reply_raw;
  end

  // Store only finished tagged replies. Entries stay in their slots:
  // retirement advances the head, cancellation clears valid bits, and
  // dispatch writes the tail. Every architectural write occurs on commit.
  always_comb begin
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      pending_d[i] = pending_q[i];
      pending_d[i].finishing = arith_next_finish_valid &&
          pending_q[i].valid &&
          pending_q[i].started && pending_q[i].decoded.kind == DK_ARITH &&
          !pending_q[i].arith_done &&
          pending_q[i].issue.tag == arith_next_finish_tag;
    end
    pending_count_d = pending_count_q;
    head_d = head_q;
    sp_d = sp_q;
    lt_d = lt_q;
    for (integer i = 0; i < PENDING_DEPTH; i++)
      if ((forward_valid_o && fwd0_sel[i]) ||
          (forward1_valid_o && fwd1_sel[i])) begin
        if (slot_candidate[i].fpr_write) pending_d[i].fpr_forwarded = 1'b1;
        if (slot_candidate[i].cr_write) pending_d[i].cr_forwarded = 1'b1;
      end
    mem_incoming_result = '0;
    retiring = '0;
    local_result = finish_local_data('0, local_stage_q.move_kind,
        local_stage_q.is_move, local_stage_q.rc, local_a, local_b, local_c,
        local_stage_q.c_lt);
    if (arith_rsp_match) begin
      pending_d[arith_rsp_slot].arith = flags_of(arith_rsp);
      pending_d[arith_rsp_slot].arith_done = 1'b1;
      pending_d[arith_rsp_slot].done = 1'b1;
      if (flags_trap(flags_of(arith_rsp), fpscr_q))
        pending_d[arith_rsp_slot].st.exception = FPU_EMULATION_TRAP;
      else begin
        pending_d[arith_rsp_slot].st.fpr_write = arith_rsp.write_result;
        pending_d[arith_rsp_slot].value =
            format_reply(pending_q[arith_rsp_slot].decoded.op);
        pending_d[arith_rsp_slot].st.fpr_sp =
            CPU_602 && pending_q[arith_rsp_slot].decoded.op != FP_FCTIWZ;
        pending_d[arith_rsp_slot].st.fpr_lt =
            CPU_602 && pending_q[arith_rsp_slot].decoded.op == FP_FCTIWZ;
      end
    end
    // A store filled from the reply keeps no data once its preparation
    // faults, so the fault information written below wins.
    for (integer i = 0; i < PENDING_DEPTH; i++)
      if (pending_q[i].store_fill) begin
        pending_d[i].value = reply_raw;
        pending_d[i].store_fill = 1'b0;
      end
    if (mem_rsp_match && mem_rsp_ready_o) begin
      mem_incoming_result = memory_result(entry_result(pending_q[mem_rsp_slot]),
          pending_q[mem_rsp_slot].decoded.mem_load,
          pending_q[mem_rsp_slot].decoded.mem_single, mem_rsp_i);
      // A filled stfd's trap outranks its preparation's fault.
      if (!(CPU_602 &&
            pending_q[mem_rsp_slot].st.exception == FPU_EMULATION_TRAP)) begin
        pending_d[mem_rsp_slot].st = status_of(mem_incoming_result);
        if (mem_rsp_i.fault || pending_q[mem_rsp_slot].decoded.mem_load)
          pending_d[mem_rsp_slot].value =
              value_of(DK_MEMORY, mem_incoming_result);
      end
      pending_d[mem_rsp_slot].done = 1'b1;
    end
    // An stfd filled from the reply checks the filled word; its access
    // was prepared without the check and is never published.
    for (integer i = 0; i < PENDING_DEPTH; i++)
      if (CPU_602 && pending_q[i].store_fill &&
          !pending_q[i].decoded.mem_single &&
          !pending_q[i].decoded.mem_integer &&
          stfd_traps(reply_raw[30:0])) begin
        pending_d[i].st.exception = FPU_EMULATION_TRAP;
        pending_d[i].st.gpr_update = 1'b0;
        pending_d[i].st.store = 1'b0;
      end
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (exec_pick[i]) begin
        pending_d[i] = record_launch(pending_d[i], launch0);
        if (exec_fire) pending_d[i] = launched(pending_d[i], launch0);
      end
      if (second_pick[i]) begin
        pending_d[i] = record_launch(pending_d[i], launch1);
        if (work1_fire) pending_d[i] = launched(pending_d[i], launch1);
      end
    end
    for (integer i = 0; i < PENDING_DEPTH; i++)
      if (pending_q[i].valid &&
          pending_q[i].started && !pending_q[i].done &&
          pending_q[i].local_wait != 2'd0) begin
        if (local_stage_q.valid &&
            local_stage_q.tag == pending_q[i].issue.tag &&
            pending_q[i].local_wait == 2'd3 &&
            (pending_q[i].decoded.kind == DK_MOVE ||
             pending_q[i].decoded.kind == DK_FSEL)) begin
          if (pending_q[i].st.exception == FPU_NO_EXCEPTION) begin
            pending_d[i].st.exception = local_result.exception;
            pending_d[i].st.fpr_write = local_result.fpr_write;
            pending_d[i].st.fpr_sp = local_result.fpr_sp;
            pending_d[i].st.cr_write = local_result.cr_write;
            pending_d[i].st.cr_field = local_result.cr_field;
            pending_d[i].value = local_result.fpr_value;
          end
        end
        pending_d[i].local_wait = pending_q[i].local_wait - 2'd1;
        if (pending_q[i].local_wait == 2'd1) pending_d[i].done = 1'b1;
      end
    if (retire_fire) pending_d[head_q].valid = 1'b0;
    if (retire1_fire) pending_d[head1_q].valid = 1'b0;
    head_d = slot_of(head_q, 3'(retire_count));
    pending_count_d = after_retire_count;
    // A retiring producer's value is in the register file next cycle.
    retiring = '0;
    if (retire_fire) retiring[head_q] = 1'b1;
    if (retire1_fire) retiring[head1_q] = 1'b1;
    for (integer i = 0; i < PENDING_DEPTH; i++)
      for (integer k = 0; k < 3; k++)
        pending_d[i].producer[k] &= ~retiring;
    // Register-file writes refresh the tracked selector classes; the
    // second port wins on a shared index.
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (fpr_we[0] && fpr_waddr[0] == pending_q[i].src_a)
        pending_d[i].a_class = fpr_wdata[0][FPR_BITS];
      if (fpr_we[1] && fpr_waddr[1] == pending_q[i].src_a)
        pending_d[i].a_class = fpr_wdata[1][FPR_BITS];
    end
    // A free tail slot takes the presented instruction every cycle; only
    // its flags wait for the dispatch handshake. Each slot reads only its
    // own next state.
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (space_ok && tail_q == PENDING_IDX_BITS'(i)) begin
        pending_d[i] = new_entry(pending_d[i], issue_i, decoded,
            lane_index[0][0], issue_ea);
        pending_d[i].a_class = class_now(lane_index[0][0],
            fpr_rdata[work_dispatch ? 0 : 3][FPR_BITS]);
        for (integer k = 0; k < 3; k++)
          pending_d[i].producer[k] =
              (work_dispatch ? bind0[k] : bind1[k]) & ~retiring;
        pending_d[i] = record_launch(pending_d[i],
            work_dispatch ? launch0 : launch1);
        if (dispatch_fire) begin
          pending_d[i] = dispatched(pending_d[i]);
          if (work_dispatch && exec_fire)
            pending_d[i] = launched(pending_d[i], launch0);
          if (exec_found && work1_fire)
            pending_d[i] = launched(pending_d[i], launch1);
        end
      end
      if (space1_ok && tail1_q == PENDING_IDX_BITS'(i)) begin
        pending_d[i] = new_entry(pending_d[i], issue1_i, decoded1,
            lane_index[1][0], issue1_ea);
        pending_d[i].a_class = class_now(lane_index[1][0],
            fpr_rdata[3][FPR_BITS]);
        // A source written by the paired lane-0 instruction binds to it.
        for (integer k = 0; k < 3; k++)
          pending_d[i].producer[k] =
              dec_write && issue_i.insn[25:21] == lane_index[1][k] ?
              PENDING_DEPTH'(1) << tail_q : bind1[k] & ~retiring;
        pending_d[i] = record_launch(pending_d[i], launch1);
        if (dispatch1_fire) begin
          pending_d[i] = dispatched(pending_d[i]);
          if (work1_fire) pending_d[i] = launched(pending_d[i], launch1);
        end
      end
    end
    if (dispatch_fire) pending_count_d = after_retire_count + 3'd1;
    if (dispatch1_fire) pending_count_d = after_retire_count + 3'd2;
    if (abort_match) begin
      for (integer i = 0; i < PENDING_DEPTH; i++)
        if (aborted[i]) pending_d[i].valid = 1'b0;
      pending_count_d = abort_index;
    end
    if (kill_all_i) begin
      for (integer i = 0; i < PENDING_DEPTH; i++) pending_d[i].valid = 1'b0;
      pending_count_d = '0;
    end
    if (retire_fire && (head_result.exception == FPU_NO_EXCEPTION ||
                        head_result.exception == FPU_FP_ENABLED)) begin
      if (CPU_602 && head_result.fpr_write) begin
        sp_d[31-head_result.fpr_index] = head_result.fpr_sp;
        lt_d[31-head_result.fpr_index] = head_result.fpr_lt;
      end
      if (CPU_602 && pv[0].decoded.kind == DK_MTSPR) begin
        if (pv[0].decoded.spr_sp) sp_d = pv[0].issue.gpr_b;
        else lt_d = pv[0].issue.gpr_b;
      end
    end
    // Rename credits and the barrier follow retirement and dispatch;
    // an abort, which excludes both, recounts the survivors.
    fpr_count_d = fpr_count_q -
        3'(retire_fire && pv[0].dest_fpr) - 3'(retire1_fire && pv[1].dest_fpr) +
        3'(dispatch_fire && dec_write) + 3'(dispatch1_fire && dec1_write);
    barrier_d = (barrier_q && !(retire_fire &&
        is_barrier(pv[0].decoded.kind, pv[0].decoded.op))) ||
        (dispatch_fire && is_barrier(decoded.kind, decoded.op));
    if (abort_match) begin
      fpr_count_d = '0;
      barrier_d = 1'b0;
      for (integer i = 0; i < PENDING_DEPTH; i++)
        if (pending_q[i].valid && !aborted[i]) begin
          fpr_count_d += {2'd0, pending_q[i].dest_fpr};
          barrier_d |= is_barrier(pending_q[i].decoded.kind,
                                  pending_q[i].decoded.op);
        end
    end
    if (kill_all_i) begin
      fpr_count_d = '0;
      barrier_d = 1'b0;
    end
  end

  assign offer_held = offer_q && offer_tag_q == work_issue.tag;
  assign work1_offer_held = offer_q && offer_tag_q == work1_issue.tag;
  always_ff @(posedge clk_i) begin
    offer_q <= rst_ni && mem_req_valid_o && !mem_req_ready_i;
    offer_tag_q <= mem_req_o.tag;
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      local_stage_q <= '0;
      for (integer i = 0; i < PENDING_DEPTH; i++) pending_q[i] <= '0;
      pending_count_q <= '0;
      head_q <= '0;
      for (integer t = 0; t < PENDING_DEPTH; t++)
        for (integer u = 0; u < PENDING_DEPTH; u++)
          older_q[t][u] <= t < u;
      head1_q <= PENDING_IDX_BITS'(1);
      tail_q <= '0;
      tail1_q <= PENDING_IDX_BITS'(1);
      fpr_count_q <= '0;
      barrier_q <= 1'b0;
      fpscr_q <= '0;
      sp_q <= '0;
      lt_q <= '0;
      deferred_abort_flush_q <= 1'b0;
    end else begin
      local_stage_q <= local_stage_d;
      local_stage_q.valid <= local_stage_d.valid && !kill_all_i;
      for (integer i = 0; i < PENDING_DEPTH; i++) pending_q[i] <= pending_d[i];
      pending_count_q <= pending_count_d;
      head_q <= head_d;
      for (integer t = 0; t < PENDING_DEPTH; t++)
        for (integer u = 0; u < PENDING_DEPTH; u++)
          older_q[t][u] <= age_of(head_d, PENDING_IDX_BITS'(t)) <
              age_of(head_d, PENDING_IDX_BITS'(u));
      head1_q <= slot_of(head_d, 3'd1);
      tail_q <= slot_of(head_d, pending_count_d);
      tail1_q <= slot_of(head_d, pending_count_d + 3'd1);
      fpr_count_q <= fpr_count_d;
      barrier_q <= barrier_d;
      sp_q <= sp_d;
      lt_q <= lt_d;
      if (kill_all_i || safe_abort_flush || deferred_abort_flush)
        deferred_abort_flush_q <= 1'b0;
      else if (abort_match)
        deferred_abort_flush_q <= 1'b1;
      if (retire_fire &&
          (head_result.exception == FPU_NO_EXCEPTION ||
           head_result.exception == FPU_FP_ENABLED) &&
          head_result.fpscr_write)
        fpscr_q <= head_result.fpscr_value;
    end
  end

  assign fpr_we[0] = retire_fire && head_result.fpr_write &&
      (head_result.exception == FPU_NO_EXCEPTION ||
       head_result.exception == FPU_FP_ENABLED);
  assign fpr_we[1] = retire1_fire && second_result.fpr_write;
  assign fpr_waddr[0] = head_result.fpr_index;
  assign fpr_waddr[1] = second_result.fpr_index;
  assign fpr_wdata[0] = {selects_b(head_result.fpr_value),
                         FPR_BITS'(head_result.fpr_value)};
  assign fpr_wdata[1] = {selects_b(second_result.fpr_value),
                         FPR_BITS'(second_result.fpr_value)};

  // Read indices repeat the work-slot selection so the storage reads do not
  // loop through the issue logic that consumes them.
  // The inspection port shares the second context's frC read and is valid
  // while that context is empty.
  always_comb begin
    logic [15:6] insn0;
    logic [15:6] insn1;
    logic context1;
    insn0 = '0;
    if (exec_found) insn0 = exec_entry.issue.insn[15:6];
    else if (issue_valid_i) insn0 = issue_i.insn[15:6];
    insn1 = '0;
    context1 = 1'b1;
    if (second_exec_found) insn1 = second_entry.issue.insn[15:6];
    else if (exec_found && issue_valid_i) insn1 = issue_i.insn[15:6];
    else if (!exec_found && issue1_valid_i) insn1 = issue1_i.insn[15:6];
    else context1 = 1'b0;
    fpr_raddr[0] = exec_found ? exec_entry.src_a : lane_index[0][0];
    fpr_raddr[1] = insn0[15:11];
    fpr_raddr[2] = insn0[10:6];
    fpr_raddr[3] = second_exec_found ? second_entry.src_a :
        lane_index[exec_found ? 0 : 1][0];
    fpr_raddr[4] = insn1[15:11];
    fpr_raddr[5] = context1 ? insn1[10:6] : inspect_fpr_index_i;
  end

  ppc_fpu_fprs #(.WIDTH(FPR_BITS + 1), .READS(6)) fprs (
    .clk_i,
    .rst_ni,
    .we_i(fpr_we),
    .waddr_i(fpr_waddr),
    .wdata_i(fpr_wdata),
    .raddr_i(fpr_raddr),
    .rdata_o(fpr_rdata)
  );
  assign inspect_fpr_o = {{(64-FPR_BITS){1'b0}}, fpr_rdata[5][FPR_BITS-1:0]};
  assign inspect_fpscr_o = fpscr_q;
  assign inspect_sp_o = CPU_602 ? sp_q : 32'd0;
  assign inspect_lt_o = CPU_602 ? lt_q : 32'd0;

  // Forwarding is independent of retirement.  Two packets preserve a CR
  // result and a load FPR result that may retire together.  A CR result has
  // priority on the first bus; remaining results stay queued for a later bus.
  // Candidates form per physical slot; the older-slot matrix orders them.
  // An older arithmetic result's sticky causes reach a younger CR1 value
  // as an OR, which is all CR1 (FX, FEX, VX, OX) reads of the prefix.
  localparam logic [31:0] STICKY_BITS = 32'h1ff8_0700;
  always_comb begin
    arith_flags_t ar, ar_known;
    logic rsp_value;
    logic [31:0] acc;
    logic [3:0] cr1;
    logic meta, reply, trap, known;
    forward_candidate_t c;
    logic [PENDING_DEPTH-1:0] ready;
    logic [PENDING_DEPTH-1:0] contributes, unknown;
    logic [PENDING_DEPTH-1:0] exc;
    logic [PENDING_DEPTH-1:0] cr_new;
    logic [PENDING_DEPTH-1:0] elig;
    logic [PENDING_DEPTH-1:0] finishing_slot;
    logic finish_trap;
    logic [2*PENDING_DEPTH-1:0] pick_open, pick_trap;
    arith_flags_t slot_ar [0:PENDING_DEPTH-1];
    logic [PENDING_DEPTH-1:0] slot_rsp_value;
    logic [PENDING_DEPTH-1:0] slot_meta, slot_reply, slot_trap;
    arith_flags_t slot_known [0:PENDING_DEPTH-1];
    logic [31:0] slot_sticky [0:PENDING_DEPTH-1];
    acc = '0;
    cr1 = '0;
    known = 1'b1;
    c = '0;
    cr_new = '0;
    elig = '0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      ar = pending_q[i].arith;
      ar_known = pending_q[i].arith;
      rsp_value = 1'b0;
      meta = pending_q[i].arith_done;
      reply = 1'b0;
      ready[i] = pending_q[i].done || pending_q[i].local_wait == 2'd1;
      if (pending_q[i].decoded.kind == DK_ARITH) begin
        // A finishing bit implies the reply this cycle unless a flush
        // cancels it, and a flush withholds every forward.
        if (!ready[i] && pending_q[i].finishing) begin
          ar = flags_of(arith_finish);
          ready[i] = 1'b1;
          meta = 1'b1;
          reply = 1'b1;
        end else if (!ready[i] && arith_rsp_match &&
                     arith_rsp.tag == pending_q[i].issue.tag) begin
          ar = flags_of(arith_rsp);
          ar_known = ar;
          rsp_value = 1'b1;
          ready[i] = 1'b1;
          meta = 1'b1;
        end
      end
      // A finishing reply's flags reach only its own trap, which selects
      // between the two picks below; its CR value and sticky causes come
      // from the registered reply.
      trap = !reply && flags_trap(ar, fpscr_q);
      slot_ar[i] = ar;
      slot_known[i] = ar_known;
      slot_rsp_value[i] = rsp_value;
      slot_meta[i] = meta;
      slot_reply[i] = reply;
      slot_trap[i] = trap;
      slot_sticky[i] = flags_fpscr(32'd0, ar_known) & STICKY_BITS;
      contributes[i] = pending_q[i].valid &&
          pending_q[i].decoded.kind == DK_ARITH && meta && !reply &&
          !flags_trap(ar_known, fpscr_q);
      // Younger CR results wait behind unknown or finishing status.
      unknown[i] = pending_q[i].valid &&
          pending_q[i].decoded.kind == DK_ARITH && (!meta || reply);
    end
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      acc = '0;
      known = 1'b1;
      for (integer j = 0; j < PENDING_DEPTH; j++)
        if (older_q[j][i]) begin
          if (contributes[j]) acc |= slot_sticky[j];
          if (unknown[j]) known = 1'b0;
        end
      slot_prefix[i] = fpscr_q | acc;
      slot_prefix[i][31] = fpscr_q[31] | (|(acc & ~fpscr_q));
      slot_prefix[i] = normalize_fpscr(slot_prefix[i]);
      c = '0;
      c.tag = pending_q[i].issue.tag;
      c.fpr_index = pending_q[i].issue.insn[25:21];
      c.fpr_write = pending_q[i].st.fpr_write;
      c.fpr_value = pending_q[i].value;
      c.fpr_sp = pending_q[i].st.fpr_sp;
      c.fpr_lt = pending_q[i].st.fpr_lt;
      c.cr_write = pending_q[i].st.cr_write;
      c.cr_field = pending_q[i].st.cr_field;
      c.cr_value = pending_q[i].st.cr_value;
      if ((pending_q[i].decoded.kind == DK_MOVE ||
           pending_q[i].decoded.kind == DK_FSEL) && c.cr_write)
        c.cr_value = slot_prefix[i][31:28];
      exc[i] = pending_q[i].st.exception != FPU_NO_EXCEPTION &&
          pending_q[i].st.exception != FPU_FP_ENABLED;
      if (pending_q[i].decoded.kind == DK_ARITH) begin
        if (slot_meta[i]) begin
          c.reply = slot_reply[i];
          c.prefix = slot_prefix[i];
          c.fctiwz = pending_q[i].decoded.op == FP_FCTIWZ;
          exc[i] = slot_trap[i];
          cr1 = 4'(flags_fpscr(slot_prefix[i], slot_known[i]) >> 28);
          c.fpr_write = slot_ar[i].write_result && !exc[i];
          c.rsp_value = slot_rsp_value[i];
          c.fpr_sp = CPU_602 && pending_q[i].decoded.op != FP_FCTIWZ;
          c.fpr_lt = CPU_602 && pending_q[i].decoded.op == FP_FCTIWZ;
          c.cr_write = !exc[i] &&
              (slot_ar[i].compare_valid || pending_q[i].issue.insn[0]);
          c.cr_field = slot_ar[i].compare_valid ?
              pending_q[i].issue.insn[25:23] : 3'd1;
          c.cr_value = slot_known[i].compare_valid ? slot_known[i].fpcc :
              cr1;
          // A finishing result's value and status come from its reply.
          if (slot_reply[i]) begin
            c.fpr_value = '0;
            c.cr_value = '0;
          end
        end
      end else if (pending_q[i].decoded.kind == DK_MEMORY && !ready[i] &&
                   mem_rsp_match && mem_rsp_i.tag == pending_q[i].issue.tag) begin
        ready[i] = 1'b1;
        exc[i] = mem_rsp_i.fault;
        if (pending_q[i].decoded.mem_load && !mem_rsp_i.fault) begin
          c.fpr_write = 1'b1;
          c.fpr_sp = CPU_602;
          c.load_value = 1'b1;
          c.load_single = pending_q[i].decoded.mem_single;
          if (!pending_q[i].decoded.mem_single) exc[i] = !load_fits;
        end
      end
      c.fpr_write = c.fpr_write && !pending_q[i].fpr_forwarded;
      cr_new[i] = c.cr_write && !pending_q[i].cr_forwarded &&
          pending_q[i].decoded.kind != DK_MCRFS &&
          (known || (pending_q[i].decoded.kind == DK_ARITH &&
                     (pending_q[i].decoded.op == FP_CMPU ||
                      pending_q[i].decoded.op == FP_CMPO)));
      c.cr_write = cr_new[i];
      elig[i] = pending_q[i].valid && ready[i] && !exc[i] &&
          (c.fpr_write || c.cr_write);
      slot_candidate[i] = c;
    end
    // At most one slot finishes. Its trap only removes it from the
    // eligible set, so both picks form beside the rounder.
    finishing_slot = slot_reply & ready;
    finish_trap = flags_trap(flags_of(arith_finish), fpscr_q);
    pick_open = forward_pick(elig, cr_new);
    pick_trap = forward_pick(elig & ~finishing_slot, cr_new);
    {fwd1_sel, fwd0_sel} = finish_trap ? pick_trap : pick_open;
    fwd0 = '0;
    fwd1 = '0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (fwd0_sel[i]) fwd0 |= slot_candidate[i];
      if (fwd1_sel[i]) fwd1 |= slot_candidate[i];
    end
    fwd0.fpr_value = arriving_value(fwd0);
    fwd1.fpr_value = arriving_value(fwd1);
    forward_valid_o = rst_ni && !kill_all_i && !abort_valid_i && |fwd0_sel;
    forward1_valid_o = rst_ni && !kill_all_i && !abort_valid_i && |fwd1_sel;
  end

  // Identity fields travel in the notification, not the payload.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic forward_payload_t forward_payload(
      input logic valid, input forward_candidate_t candidate);
  /* verilator lint_on UNUSEDSIGNAL */
    forward_payload_t out;
    out.valid = valid;
    out.reply = candidate.reply;
    out.prefix = candidate.prefix;
    out.fctiwz = candidate.fctiwz;
    out.data.fpr_value = candidate.fpr_value;
    out.data.fpr_sp = candidate.fpr_sp;
    out.data.fpr_lt = candidate.fpr_lt;
    out.data.cr_value = candidate.cr_value;
    return out;
  endfunction

  // A payload announced with a finishing result comes from the registered
  // reply and the status prefix captured at the announcement.
  function automatic ppc_fpu_forward_data_t payload_data(
      input forward_payload_t payload);
    ppc_fpu_forward_data_t out;
    // CR1 copies only the status high nibble.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] status;
    /* verilator lint_on UNUSEDSIGNAL */
    out = payload.data;
    if (payload.reply) begin
      status = arithmetic_fpscr(payload.prefix, arith_rsp.invalid,
          arith_rsp.ox, arith_rsp.ux, arith_rsp.zx, arith_rsp.xx,
          arith_rsp.fr, arith_rsp.fi, arith_rsp.frfi_valid, arith_rsp.fprf,
          arith_rsp.fprf_valid, arith_rsp.fpcc, arith_rsp.compare_valid);
      out.fpr_value = CPU_602 ?
          {32'd0, (payload.fctiwz ? arith_rsp.result[31:0] :
           reply_raw[31:0])} : arith_rsp.result;
      out.cr_value = arith_rsp.compare_valid ? arith_rsp.fpcc :
          status[31:28];
    end
    if (!payload.valid) out = '0;
    return out;
  endfunction

  assign forward_o = '{tag: fwd0.tag, fpr_write: fwd0.fpr_write,
      fpr_index: fwd0.fpr_index, cr_write: fwd0.cr_write,
      cr_field: fwd0.cr_field};
  assign forward1_o = '{tag: fwd1.tag, fpr_write: fwd1.fpr_write,
      fpr_index: fwd1.fpr_index, cr_write: fwd1.cr_write,
      cr_field: fwd1.cr_field};
  assign fwd0_payload_d = forward_payload(forward_valid_o, fwd0);
  assign fwd1_payload_d = forward_payload(forward1_valid_o, fwd1);
  assign forward_data_o = payload_data(fwd0_payload_q);
  assign forward1_data_o = payload_data(fwd1_payload_q);

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      fwd0_payload_q <= '0;
      fwd1_payload_q <= '0;
    end else begin
      fwd0_payload_q <= fwd0_payload_d;
      fwd1_payload_q <= fwd1_payload_d;
    end
  end
endmodule
`default_nettype wire
