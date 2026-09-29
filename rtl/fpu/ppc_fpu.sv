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
  } source_t;
  typedef struct packed {
    logic [63:0] raw;
    logic sp;
  } local_operand_t;
  typedef struct packed {
    logic valid;
    logic started;
    logic done;
    logic finishing;
    logic dest_fpr;
    ppc_fpu_issue_t issue;
    decoded_t decoded;
    ppc_fpu_result_t result;
    ppc_fpu_arith_rsp_t arith;
    logic arith_done;
    logic fpr_forwarded;
    logic cr_forwarded;
    logic [1:0] local_wait;
    ppc_fpu_mem_t mem;
    logic store_fill;
  } pending_t;
  typedef struct packed {
    logic valid;
    completion_tag_t tag;
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
  // Entries in age order; pv[0] is the head.
  pending_t pv [0:PENDING_DEPTH-1];
  logic [PENDING_IDX_BITS-1:0] head_q, head_d;
  logic [PENDING_IDX_BITS-1:0] head1_q, tail_q, tail1_q;
  logic [PENDING_IDX_BITS-1:0] arith_rsp_slot, mem_rsp_slot;
  logic [PENDING_IDX_BITS-1:0] exec_slot, work1_old_slot;
  logic [PENDING_IDX_BITS-1:0] forward_slot, forward1_slot;
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
  logic arith_rsp_ready;
  logic arith_finish_valid;
  logic arith_finish_write;
  logic arith_next_finish_valid;
  completion_tag_t arith_next_finish_tag;
  logic [2:0] arith_req_fwd;
  local_operand_t local_a, local_b, local_c;
  logic [2:0] fpr_count_q;
  logic [2:0] fpr_count_d;
  logic barrier_q;
  logic barrier_d;
  logic [FPR_BITS-1:0] fpr_q [0:31];
  logic [31:0] fpscr_q;
  logic [31:0] proposed_fpscr;
  logic [31:0] issue_ea;
  logic [63:0] src_a;
  logic [63:0] src_b;
  logic [63:0] src_c;
  logic [30:0] src_d;
  logic [30:0] work1_d_raw;
  logic [30:0] finish_store_word;
  logic finish_trap;
  logic store_d_ready, work1_store_d_ready;
  logic src_a_sp, src_b_sp, src_c_sp, src_d_sp;
  logic src_b_lt, src_d_lt;
  source_t source_a, source_b, source_c, source_d;
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
  logic forward_from_pending;
  logic [PENDING_IDX_BITS-1:0] forward_index;
  logic forward1_from_pending;
  logic [PENDING_IDX_BITS-1:0] forward1_index;
  logic [PENDING_IDX_BITS-1:0] abort_index;
  logic abort_index_valid;
  logic safe_abort_flush;
  logic deferred_abort_flush_q;
  logic deferred_abort_flush;
  logic older_arith_pending;
  logic sources_ready;
  logic [PENDING_IDX_BITS-1:0] exec_index;
  logic exec_found;
  logic second_exec_found;
  logic [PENDING_IDX_BITS-1:0] second_exec_index;
  logic exec_fire;
  logic arith_rsp_match;
  logic mem_rsp_match;
  logic [PENDING_IDX_BITS-1:0] arith_rsp_index;
  logic [PENDING_IDX_BITS-1:0] mem_rsp_index;
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
  logic [31:0] prefix_fpscr;
  forward_candidate_t fwd0;
  forward_candidate_t fwd1;
  forward_payload_t fwd0_payload_d, fwd0_payload_q;
  forward_payload_t fwd1_payload_d, fwd1_payload_q;
  logic prefix_known;
  work_t work_issue;
  decoded_t work_decoded;
  logic work_dispatch;
  logic work_admitted;
  logic [31:0] work_ea;
  logic [4:0] src_a_index, src_b_index, src_c_index, src_d_index;
  logic arith_launch;
  logic mem_launch;
  logic local_launch;
  logic arith_eligible;
  logic mem_eligible;
  logic local_fpu_uses_pipe;
  ppc_fpu_result_t mem_incoming_result;
  logic commit_match;
  logic abort_match;
  work1_t work1_issue;
  decoded_t work1_decoded;
  logic [31:0] work1_ea;
  logic work1_valid;
  logic work1_old;
  logic work1_admitted;
  logic [PENDING_IDX_BITS-1:0] work1_old_index;
  source_t work1_a, work1_b, work1_c, work1_d;
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
  ppc_fpu_arith_req_t work1_arith_req;
  ppc_fpu_mem_t work1_mem_req;
  ppc_fpu_mem_t mem_pending;
  ppc_fpu_mem_t work1_mem_pending;
  logic mem_fill;
  logic work1_mem_fill;
  logic [63:0] reply_raw;
  ppc_fpu_result_t work1_result;

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
          widen_single(raw[31:0]);
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

  function automatic ppc_fpu_result_t numeric_result(
      input ppc_fpu_result_t base, input ppc_fpu_arith_rsp_t ar,
      input ppc_fpu_op_t op, input logic rc, input logic [2:0] cr_field,
      input logic fe0, input logic fe1, input logic [31:0] old_f
  );
    ppc_fpu_result_t out;
    logic [31:0] next_f;
    begin
      out = base;
      out.tag = ar.tag;
      next_f = arithmetic_fpscr(old_f, ar.invalid, ar.ox,
          ar.ux, ar.zx, ar.xx, ar.fr,
          ar.fi, ar.frfi_valid, ar.fprf,
          ar.fprf_valid, ar.fpcc, ar.compare_valid);
      if (numeric_emulation_trap(ar.invalid, ar.ox, ar.ux, ar.zx,
                                 ar.xx, ar.tiny_before_round, old_f[7:2])) begin
        out.exception = FPU_EMULATION_TRAP;
        out.fpr_write = 1'b0;
        out.fpscr_write = 1'b0;
        out.cr_write = 1'b0;
      end else begin
        out.fpr_write = ar.write_result;
        out.fpr_value = CPU_602 ?
            {32'd0, (op == FP_FCTIWZ ? ar.result[31:0] :
              narrow_single(ar.result))} : ar.result;
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

  function automatic source_t read_source(input logic [4:0] reg_index,
                                          input logic [2:0] older_count);
    source_t s;
    begin
      s = '0;
      s.ready = 1'b1;
      s.raw = {{(64-FPR_BITS){1'b0}}, fpr_q[reg_index]};
      s.sp = CPU_602 && sp_q[31-reg_index];
      s.lt = CPU_602 && lt_q[31-reg_index];
      for (integer i = 0; i < PENDING_DEPTH; i++) begin
        if (i < int'(older_count) && pv[i].valid &&
            pv[i].dest_fpr && pv[i].issue.insn[25:21] == reg_index) begin
          s.ready = 1'b0;
          if ((pv[i].done || pv[i].local_wait == 2'd1) &&
              pv[i].result.fpr_write &&
              pv[i].result.exception == FPU_NO_EXCEPTION) begin
            s.ready = 1'b1;
            s.raw = pv[i].result.fpr_value;
            s.sp = pv[i].result.fpr_sp;
            s.lt = pv[i].result.fpr_lt;
          end else if (pv[i].finishing && arith_finish_write) begin
            // The value exists only at the arithmetic input and local-stage
            // forward points; other consumers wait for the registered reply.
            // A trapping value aborts every younger consumer before it
            // commits, so only stores wait on the trap check.
            s.ready = 1'b1;
            s.fwd = 1'b1;
            s.raw = '0;
            s.sp = CPU_602 && pv[i].decoded.op != FP_FCTIWZ;
            s.lt = CPU_602 && pv[i].decoded.op == FP_FCTIWZ;
          end else if (arith_rsp_valid && arith_rsp.tag == pv[i].issue.tag &&
                       !numeric_emulation_trap(arith_rsp.invalid, arith_rsp.ox,
                           arith_rsp.ux, arith_rsp.zx, arith_rsp.xx,
                           arith_rsp.tiny_before_round, fpscr_q[7:2]) &&
                       arith_rsp.write_result) begin
            s.ready = 1'b1;
            s.raw = CPU_602 ?
                {32'd0, (pv[i].decoded.op == FP_FCTIWZ ?
                  arith_rsp.result[31:0] : narrow_single(arith_rsp.result))} :
                arith_rsp.result;
            s.sp = CPU_602 && pv[i].decoded.op != FP_FCTIWZ;
            s.lt = CPU_602 && pv[i].decoded.op == FP_FCTIWZ;
          end else if (mem_rsp_match && mem_rsp_index == PENDING_IDX_BITS'(i) &&
                       mem_rsp_i.tag == pv[i].issue.tag &&
                       pv[i].decoded.kind == DK_MEMORY &&
                       pv[i].decoded.mem_load && !mem_rsp_i.fault &&
                       (!CPU_602 || pv[i].decoded.mem_single ||
                        single_fits_double(mem_rsp_i.data))) begin
            s.ready = 1'b1;
            s.raw = CPU_602 ?
                {32'd0,(pv[i].decoded.mem_single ?
                  mem_rsp_i.data[31:0] : narrow_single(mem_rsp_i.data))} :
                (pv[i].decoded.mem_single ?
                  widen_single(mem_rsp_i.data[31:0]) : mem_rsp_i.data);
            s.sp = CPU_602;
            s.lt = 1'b0;
          end
        end
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
        if (CPU_602) begin
          r.fpr_value = {32'd0,reply.data[31:0]};
          r.fpr_sp = 1'b1;
          if (!mem_single) begin
            if (!single_fits_double(reply.data)) begin
              r.exception = FPU_EMULATION_TRAP;
              r.fpr_write = 1'b0;
              r.gpr_update = 1'b0;
            end else r.fpr_value = {32'd0,narrow_single(reply.data)};
          end
        end else r.fpr_value = mem_single ?
            widen_single(reply.data[31:0]) : reply.data;
      end
      return r;
    end
  endfunction

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
    for (integer k = 0; k < PENDING_DEPTH; k++)
      pv[k] = pending_q[slot_of(head_q, 3'(k))];
    arith_rsp_slot = slot_of(head_q, 3'(arith_rsp_index));
    mem_rsp_slot = slot_of(head_q, 3'(mem_rsp_index));
    exec_slot = slot_of(head_q, 3'(exec_index));
    work1_old_slot = slot_of(head_q, 3'(work1_old_index));
    forward_slot = slot_of(head_q, 3'(forward_index));
    forward1_slot = slot_of(head_q, 3'(forward1_index));
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

  // One waiting reservation entry is permitted. Ready independent operands
  // bypass it and enter the arithmetic pipe on the dispatch handshake.
  always_comb begin
    exec_found = 1'b0;
    exec_index = '0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (!exec_found && i < int'(pending_count_q) &&
          pv[i].valid && !pv[i].started) begin
        exec_found = 1'b1;
        exec_index = PENDING_IDX_BITS'(i);
      end
    end
    second_exec_found = 1'b0;
    second_exec_index = '0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (exec_found && !second_exec_found &&
          i < int'(pending_count_q) && pv[i].valid &&
          !pv[i].started && i != int'(exec_index) &&
          ((is_fpu_exec(pv[exec_index].decoded.kind) &&
            pv[i].decoded.kind == DK_MEMORY) ||
           (pv[exec_index].decoded.kind == DK_MEMORY &&
            is_fpu_exec(pv[i].decoded.kind)))) begin
        second_exec_found = 1'b1;
        second_exec_index = PENDING_IDX_BITS'(i);
      end
    end
    barrier_present = barrier_q;
    duplicate_tag = 1'b0;
    duplicate1_tag = 1'b0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (i < int'(pending_count_q) && pv[i].valid) begin
        if (pv[i].issue.tag == issue_i.tag) duplicate_tag = 1'b1;
        if (pv[i].issue.tag == issue1_i.tag) duplicate1_tag = 1'b1;
      end
    end
  end

  always_comb begin
    arith_rsp_match = 1'b0;
    mem_rsp_match = 1'b0;
    arith_rsp_index = '0;
    mem_rsp_index = '0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (i < int'(pending_count_q) && pv[i].valid) begin
        if (arith_rsp_valid && pv[i].started &&
            pv[i].decoded.kind == DK_ARITH &&
            pv[i].issue.tag == arith_rsp.tag) begin
          arith_rsp_match = 1'b1;
          arith_rsp_index = PENDING_IDX_BITS'(i);
        end
        if (mem_rsp_valid_i && pv[i].started &&
            pv[i].decoded.kind == DK_MEMORY &&
            pv[i].issue.tag == mem_rsp_i.tag) begin
          mem_rsp_match = 1'b1;
          mem_rsp_index = PENDING_IDX_BITS'(i);
        end
      end
    end
  end

  always_comb begin
    abort_index = '0;
    abort_index_valid = 1'b0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (i < int'(pending_count_q) && pv[i].valid &&
          pv[i].issue.tag == abort_tag_i) begin
        abort_index = PENDING_IDX_BITS'(i);
        abort_index_valid = 1'b1;
      end
    end
    safe_abort_flush = abort_valid_i && abort_index_valid;
    for (integer i = 0; i < PENDING_DEPTH; i++)
      if (i < int'(abort_index) && pv[i].valid &&
          pv[i].decoded.kind == DK_ARITH &&
          pv[i].started && !pv[i].arith_done &&
          !pv[i].done)
        safe_abort_flush = 1'b0;
    older_arith_pending = 1'b0;
    for (integer i = 0; i < PENDING_DEPTH; i++)
      if (i < int'(pending_count_q) && pv[i].valid &&
          pv[i].decoded.kind == DK_ARITH &&
          pv[i].started && !pv[i].arith_done &&
          !pv[i].done) older_arith_pending = 1'b1;
    deferred_abort_flush = deferred_abort_flush_q && !older_arith_pending;
  end

  always_comb begin
    head_result = '0;
    head_available = pending_count_q != 3'd0 && pv[0].valid;
    if (head_available) begin
      head_result = pv[0].result;
      if ((pv[0].decoded.kind == DK_MOVE ||
           pv[0].decoded.kind == DK_FSEL) && head_result.cr_write)
        head_result.cr_value = fpscr_q[31:28];
      if (pv[0].decoded.kind == DK_ARITH) begin
        if (pv[0].arith_done)
          head_result = numeric_result(pv[0].result, pv[0].arith,
              pv[0].decoded.op, pv[0].issue.insn[0],
              pv[0].issue.insn[25:23],
              pv[0].issue.msr_fe0, pv[0].issue.msr_fe1, fpscr_q);
        else if (arith_rsp_match && arith_rsp_index == '0) begin
          head_result = numeric_result(pv[0].result, arith_rsp,
              pv[0].decoded.op, pv[0].issue.insn[0],
              pv[0].issue.insn[25:23],
              pv[0].issue.msr_fe0,
              pv[0].issue.msr_fe1, fpscr_q);
        end
      end else if (pv[0].decoded.kind == DK_MEMORY &&
                   mem_rsp_match && mem_rsp_index == '0) begin
        head_result = memory_result(pv[0].result,
            pv[0].decoded.mem_load, pv[0].decoded.mem_single,
            mem_rsp_i);
      end
    end
    commit_match = head_available && commit_valid_i &&
        commit_tag_i == pv[0].issue.tag;
    matching_abort = abort_index_valid;
    abort_match = abort_valid_i && matching_abort;
    result_valid_o = rst_ni && !kill_all_i && !abort_match &&
        head_available && (pv[0].done ||
          pv[0].local_wait == 2'd1 ||
          (pv[0].decoded.kind == DK_ARITH &&
           arith_rsp_match && arith_rsp_index == '0) ||
          (pv[0].decoded.kind == DK_MEMORY &&
           mem_rsp_match && mem_rsp_index == '0));
    result_o = head_result;
    second_result = '0;
    if (pending_count_q > 3'd1 && pv[1].valid) begin
      second_result = pv[1].result;
      if (pv[1].decoded.kind == DK_MEMORY &&
          mem_rsp_match && mem_rsp_index == PENDING_IDX_BITS'(1))
        second_result = memory_result(pv[1].result,
            pv[1].decoded.mem_load,
            pv[1].decoded.mem_single, mem_rsp_i);
    end
    result1_valid_o = !CPU_602 && result_valid_o &&
        pending_count_q > 3'd1 && pv[1].valid &&
        pv[1].decoded.kind == DK_MEMORY &&
        pv[1].decoded.mem_load &&
        (pv[1].done ||
         (mem_rsp_match && mem_rsp_index == PENDING_IDX_BITS'(1))) &&
        head_result.exception == FPU_NO_EXCEPTION &&
        !head_result.fpr_write &&
        second_result.exception == FPU_NO_EXCEPTION &&
        second_result.fpr_write;
    result1_o = second_result;
    store_o = pv[0].mem;
    if (pv[0].store_fill)
      store_o.data = store_data(pv[0].decoded.mem_integer,
          pv[0].decoded.mem_single, reply_raw);
    store_valid_o = result_valid_o && head_result.store && commit_match;
    commit_ready_o = result_valid_o && commit_match &&
        (!head_result.store || store_ready_i);
    retire_fire = commit_ready_o;
    commit1_ready_o = result1_valid_o && retire_fire &&
        commit1_valid_i && commit1_tag_i == pv[1].issue.tag;
    retire1_fire = commit1_ready_o;
    retire_count = {1'b0,retire_fire} + {1'b0,retire1_fire};
    after_retire_count = pending_count_q - {1'b0,retire_count};
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
        (pair_ok && is_fpu_exec(pv[exec_index].decoded.kind));
    ready_if_exec = (!exec_found ||
        (pair_ok && pv[exec_index].decoded.kind == DK_MEMORY)) && !div_busy;
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
      work_issue.tag = pv[exec_index].issue.tag;
      work_issue.insn = pv[exec_index].issue.insn;
      work_issue.msr_fp = pv[exec_index].issue.msr_fp;
      work_issue.msr_fe0 = pv[exec_index].issue.msr_fe0;
      work_issue.msr_fe1 = pv[exec_index].issue.msr_fe1;
      work_issue.msr_pr = pv[exec_index].issue.msr_pr;
      work_decoded = pv[exec_index].decoded;
      work_ea = pv[exec_index].result.ea;
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
    src_a_index = work_issue.insn[20:16];
    src_b_index = work_issue.insn[15:11];
    src_c_index = work_issue.insn[10:6];
    src_d_index = work_issue.insn[25:21];
    source_a = read_source(src_a_index, work_dispatch ?
        pending_count_q : 3'(exec_index));
    source_b = read_source(src_b_index, work_dispatch ?
        pending_count_q : 3'(exec_index));
    source_c = read_source(src_c_index, work_dispatch ?
        pending_count_q : 3'(exec_index));
    source_d = read_source(src_d_index, work_dispatch ?
        pending_count_q : 3'(exec_index));
    src_a = source_a.raw;
    src_b = source_b.raw;
    src_c = source_c.raw;
    src_d = source_d.fwd ? finish_store_word : source_d.raw[30:0];
    store_d_ready = source_d.ready && !(source_d.fwd && finish_trap);
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
    select_b = CPU_602 ?
        (((src_a[30:23] == 8'hff) && src_a[22:0] != 23'd0) ||
         (src_a[31] && src_a[30:0] != 31'd0)) :
        (((src_a[62:52] == 11'h7ff) && src_a[51:0] != 52'd0) ||
         (src_a[63] && src_a[62:0] != 63'd0));
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
    work1_old_index = '0;
    if (second_exec_found) begin
      work1_issue.tag = pv[second_exec_index].issue.tag;
      work1_issue.insn = pv[second_exec_index].issue.insn;
      work1_issue.msr_fp = pv[second_exec_index].issue.msr_fp;
      work1_decoded = pv[second_exec_index].decoded;
      work1_ea = pv[second_exec_index].result.ea;
      work1_valid = 1'b1;
      work1_old = 1'b1;
      work1_old_index = second_exec_index;
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
    work1_a = read_source(work1_issue.insn[20:16],
        work1_old ? 3'(work1_old_index) : pending_count_q);
    work1_b = read_source(work1_issue.insn[15:11],
        work1_old ? 3'(work1_old_index) : pending_count_q);
    work1_c = read_source(work1_issue.insn[10:6],
        work1_old ? 3'(work1_old_index) : pending_count_q);
    work1_d = read_source(work1_issue.insn[25:21],
        work1_old ? 3'(work1_old_index) : pending_count_q);
    work1_d_raw = work1_d.fwd ? finish_store_word : work1_d.raw[30:0];
    work1_store_d_ready = work1_d.ready && !(work1_d.fwd && finish_trap);
    work1_select_b = CPU_602 ?
        (((work1_a.raw[30:23] == 8'hff) && work1_a.raw[22:0] != 23'd0) ||
         (work1_a.raw[31] && work1_a.raw[30:0] != 31'd0)) :
        (((work1_a.raw[62:52] == 11'h7ff) &&
          work1_a.raw[51:0] != 52'd0) ||
         (work1_a.raw[63] && work1_a.raw[62:0] != 63'd0));
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
    work1_arith_req = '0;
    work1_arith_req.tag = work1_issue.tag;
    work1_arith_req.op = work1_decoded.op;
    work1_arith_req.a = CPU_602 ?
        widen_single(work1_a.raw[31:0]) : work1_a.raw;
    work1_arith_req.b = CPU_602 ?
        widen_single(work1_b.raw[31:0]) : work1_b.raw;
    work1_arith_req.c = CPU_602 ?
        widen_single(work1_c.raw[31:0]) : work1_c.raw;
    work1_arith_req.rn = fpscr_q[1:0];
    work1_arith_req.ni = fpscr_q[2];
    work1_arith_req.ve = fpscr_q[7];
    work1_arith_req.oe = fpscr_q[6];
    work1_arith_req.ue = fpscr_q[5];
    work1_arith_req.ze = fpscr_q[4];
    work1_arith_req.single_result = work1_decoded.single_result;
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
          (work1_d_raw[30:23] == 8'hff ||
           (work1_d_raw[30:23] == 8'd0 &&
            work1_d_raw[22:0] != 23'd0)));
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
    // Store data reaches the LSU only in the authorized store descriptor.
    // A source finishing this cycle is filled from the reply next cycle.
    work1_mem_pending = work1_mem_req;
    work1_mem_pending.data = store_data(work1_decoded.mem_integer,
        work1_decoded.mem_single, work1_d.raw);
    work1_mem_fill = work1_decoded.mem_store && work1_d.fwd;
    work1_fire = (work1_arith_launch && arith_req_ready) ||
        (work1_mem_launch && mem_req_ready_i) || work1_local_launch;
  end
  assign combined_arith_launch = arith_launch || work1_arith_launch;
  // The 602 store trap check is the only register-file consumer of a
  // finishing value.
  assign finish_store_word = 31'(narrow_single(arith_finish.result));
  assign finish_trap = numeric_emulation_trap(arith_finish.invalid,
      arith_finish.ox, arith_finish.ux, arith_finish.zx, arith_finish.xx,
      arith_finish.tiny_before_round, fpscr_q[7:2]);
  assign arith_req_fwd = work1_arith_launch ?
      {work1_c.fwd, work1_b.fwd, work1_a.fwd} :
      {source_c.fwd, source_b.fwd, source_a.fwd};

  always_comb begin
    arith_req = '0;
    arith_req.tag = work_issue.tag;
    arith_req.op = work_decoded.op;
    arith_req.a = CPU_602 ? widen_single(src_a[31:0]) : src_a;
    arith_req.b = CPU_602 ? widen_single(src_b[31:0]) : src_b;
    arith_req.c = CPU_602 ? widen_single(src_c[31:0]) : src_c;
    arith_req.rn = fpscr_q[1:0];
    arith_req.ni = fpscr_q[2];
    arith_req.ve = fpscr_q[7];
    arith_req.oe = fpscr_q[6];
    arith_req.ue = fpscr_q[5];
    arith_req.ze = fpscr_q[4];
    arith_req.single_result = work_decoded.single_result;
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
          (src_d[30:23] == 8'hff ||
           (src_d[30:23] == 8'd0 && src_d[22:0] != 23'd0)));
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
    mem_pending = mem_req_o;
    mem_pending.data = store_data(work_decoded.mem_integer,
        work_decoded.mem_single, source_d.raw);
    mem_fill = work_decoded.mem_store && source_d.fwd;
    if (work1_mem_launch) mem_req_o = work1_mem_req;
    mem_req_valid_o = mem_launch || work1_mem_launch;
    exec_fire = (arith_launch && arith_req_ready) ||
        (mem_launch && mem_req_ready_i) || local_launch;
  end

  ppc_fpu_arith #(.CPU_602(CPU_602)) arithmetic (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .req_valid_i(combined_arith_launch), .req_ready_o(arith_req_ready),
      .req_i(work1_arith_launch ? work1_arith_req : arith_req),
      .req_fwd_i(arith_req_fwd),
      .rsp_valid_o(arith_rsp_valid),
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
                       (src_d[30:23] == 8'hff ||
                        (src_d[30:23] == 8'd0 && src_d[22:0] != 23'd0))) begin
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
                       (work1_d_raw[30:23] == 8'hff ||
                        (work1_d_raw[30:23] == 8'd0 &&
                         work1_d_raw[22:0] != 23'd0))) begin
            work1_result.exception = FPU_EMULATION_TRAP;
            work1_result.gpr_update = 1'b0;
          end else work1_result.store = work1_decoded.mem_store;
        end
        default: ;
      endcase
    end
  end

  // Only one local FPU instruction can launch per edge. Capture its operands
  // once, with the full producer tag, then resolve MOVE/FSEL data next edge.
  always_comb begin
    local_stage_d = '0;
    if (local_launch && (work_decoded.kind == DK_MOVE ||
                         work_decoded.kind == DK_FSEL)) begin
      local_stage_d.valid = 1'b1;
      local_stage_d.tag = work_issue.tag;
      local_stage_d.move_kind = work_decoded.move_kind;
      local_stage_d.a.raw = source_a.raw;
      local_stage_d.a.sp = source_a.sp;
      local_stage_d.b.raw = source_b.raw;
      local_stage_d.b.sp = source_b.sp;
      local_stage_d.c.raw = source_c.raw;
      local_stage_d.c.sp = source_c.sp;
      local_stage_d.c_lt = source_c.lt;
      local_stage_d.fwd = {source_c.fwd, source_b.fwd, source_a.fwd};
    end else if (work1_local_launch &&
                 (work1_decoded.kind == DK_MOVE ||
                  work1_decoded.kind == DK_FSEL)) begin
      local_stage_d.valid = 1'b1;
      local_stage_d.tag = work1_issue.tag;
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

  assign reply_raw = CPU_602 ? {32'd0, narrow_single(arith_rsp.result)} :
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
    if (forward_valid_o && forward_from_pending) begin
      if (fwd0.fpr_write)
        pending_d[forward_slot].fpr_forwarded = 1'b1;
      if (fwd0.cr_write)
        pending_d[forward_slot].cr_forwarded = 1'b1;
    end
    if (forward1_valid_o && forward1_from_pending) begin
      if (fwd1.fpr_write)
        pending_d[forward1_slot].fpr_forwarded = 1'b1;
      if (fwd1.cr_write)
        pending_d[forward1_slot].cr_forwarded = 1'b1;
    end
    mem_incoming_result = '0;
    if (arith_rsp_match) begin
      pending_d[arith_rsp_slot].arith = arith_rsp;
      pending_d[arith_rsp_slot].arith_done = 1'b1;
      pending_d[arith_rsp_slot].done = 1'b1;
      if (numeric_emulation_trap(arith_rsp.invalid, arith_rsp.ox,
          arith_rsp.ux, arith_rsp.zx, arith_rsp.xx,
          arith_rsp.tiny_before_round, fpscr_q[7:2]))
        pending_d[arith_rsp_slot].result.exception = FPU_EMULATION_TRAP;
      else begin
        pending_d[arith_rsp_slot].result.fpr_write = arith_rsp.write_result;
        pending_d[arith_rsp_slot].result.fpr_value = CPU_602 ?
            {32'd0,(pv[arith_rsp_index].decoded.op == FP_FCTIWZ ?
              arith_rsp.result[31:0] : narrow_single(arith_rsp.result))} :
            arith_rsp.result;
        pending_d[arith_rsp_slot].result.fpr_sp =
            CPU_602 && pv[arith_rsp_index].decoded.op != FP_FCTIWZ;
        pending_d[arith_rsp_slot].result.fpr_lt =
            CPU_602 && pv[arith_rsp_index].decoded.op == FP_FCTIWZ;
      end
    end
    if (mem_rsp_match && mem_rsp_ready_o) begin
      mem_incoming_result = memory_result(pv[mem_rsp_index].result,
          pv[mem_rsp_index].decoded.mem_load,
          pv[mem_rsp_index].decoded.mem_single, mem_rsp_i);
      pending_d[mem_rsp_slot].result = mem_incoming_result;
      pending_d[mem_rsp_slot].done = 1'b1;
    end
    if (exec_found && exec_fire) begin
      pending_d[exec_slot].started = 1'b1;
      if (local_launch) begin
        pending_d[exec_slot].result = exec_result;
        pending_d[exec_slot].local_wait = local_latency(work_decoded.kind);
      end else if (mem_launch) begin
        pending_d[exec_slot].mem = mem_pending;
        pending_d[exec_slot].store_fill = mem_fill;
        pending_d[exec_slot].result = exec_result;
      end
    end
    if (work1_old && work1_fire) begin
      pending_d[work1_old_slot].started = 1'b1;
      if (work1_local_launch) begin
        pending_d[work1_old_slot].result = work1_result;
        pending_d[work1_old_slot].local_wait =
            local_latency(work1_decoded.kind);
      end else if (work1_mem_launch) begin
        pending_d[work1_old_slot].mem = work1_mem_pending;
        pending_d[work1_old_slot].store_fill = work1_mem_fill;
        pending_d[work1_old_slot].result = work1_result;
      end
    end
    for (integer i = 0; i < PENDING_DEPTH; i++)
      if (pending_q[i].store_fill) begin
        pending_d[i].mem.data = store_data(pending_q[i].decoded.mem_integer,
            pending_q[i].decoded.mem_single, reply_raw);
        pending_d[i].store_fill = 1'b0;
      end
    for (integer i = 0; i < PENDING_DEPTH; i++)
      if (pending_q[i].valid &&
          pending_q[i].started && !pending_q[i].done &&
          pending_q[i].local_wait != 2'd0) begin
        if (local_stage_q.valid &&
            local_stage_q.tag == pending_q[i].issue.tag &&
            pending_q[i].local_wait == 2'd3 &&
            (pending_q[i].decoded.kind == DK_MOVE ||
             pending_q[i].decoded.kind == DK_FSEL))
          pending_d[i].result = finish_local_data(pending_q[i].result,
              local_stage_q.move_kind,
              pending_q[i].decoded.kind == DK_MOVE,
              pending_q[i].issue.insn[0],
              local_a, local_b, local_c, local_stage_q.c_lt);
        pending_d[i].local_wait = pending_q[i].local_wait - 2'd1;
        if (pending_q[i].local_wait == 2'd1) pending_d[i].done = 1'b1;
      end
    if (retire_fire) pending_d[head_q].valid = 1'b0;
    if (retire1_fire) pending_d[head1_q].valid = 1'b0;
    head_d = slot_of(head_q, 3'(retire_count));
    pending_count_d = after_retire_count;
    if (dispatch_fire) begin
      pending_d[tail_q] = '0;
      pending_d[tail_q].valid = 1'b1;
      pending_d[tail_q].issue = issue_i;
      pending_d[tail_q].decoded = decoded;
      pending_d[tail_q].dest_fpr =
          writes_fpr(decoded.kind, decoded.op, decoded.mem_load);
      pending_d[tail_q].result.tag = issue_i.tag;
      pending_d[tail_q].result.ea = issue_ea;
      pending_d[tail_q].result.fpr_index = issue_i.insn[25:21];
      pending_d[tail_q].result.gpr_index = issue_i.insn[20:16];
      pending_d[tail_q].result.gpr_value = issue_ea;
      pending_d[tail_q].result.gpr_update =
          decoded.kind == DK_MEMORY && decoded.mem_update;
      pending_d[tail_q].result.cr_field = issue_i.insn[25:23];
      if (work_dispatch && exec_fire) begin
        pending_d[tail_q].started = 1'b1;
        if (local_launch) begin
          pending_d[tail_q].result = exec_result;
          pending_d[tail_q].local_wait =
              local_latency(work_decoded.kind);
        end else if (mem_launch) begin
          pending_d[tail_q].mem = mem_pending;
          pending_d[tail_q].store_fill = mem_fill;
          pending_d[tail_q].result = exec_result;
        end
      end
      if (exec_found && work1_fire) begin
        pending_d[tail_q].started = 1'b1;
        if (work1_local_launch) begin
          pending_d[tail_q].result = work1_result;
          pending_d[tail_q].local_wait =
              local_latency(work1_decoded.kind);
        end else if (work1_mem_launch) begin
          pending_d[tail_q].mem = work1_mem_pending;
          pending_d[tail_q].store_fill = work1_mem_fill;
          pending_d[tail_q].result = work1_result;
        end
      end
      pending_count_d = after_retire_count + 3'd1;
    end
    if (dispatch1_fire) begin
      pending_d[tail1_q] = '0;
      pending_d[tail1_q].valid = 1'b1;
      pending_d[tail1_q].issue = issue1_i;
      pending_d[tail1_q].decoded = decoded1;
      pending_d[tail1_q].dest_fpr =
          writes_fpr(decoded1.kind, decoded1.op, decoded1.mem_load);
      pending_d[tail1_q].result.tag = issue1_i.tag;
      pending_d[tail1_q].result.ea = issue1_ea;
      pending_d[tail1_q].result.fpr_index = issue1_i.insn[25:21];
      pending_d[tail1_q].result.gpr_index = issue1_i.insn[20:16];
      pending_d[tail1_q].result.gpr_value = issue1_ea;
      pending_d[tail1_q].result.gpr_update =
          decoded1.kind == DK_MEMORY && decoded1.mem_update;
      pending_d[tail1_q].result.cr_field = issue1_i.insn[25:23];
      if (work1_fire) begin
        pending_d[tail1_q].started = 1'b1;
        if (work1_local_launch) begin
          pending_d[tail1_q].result = work1_result;
          pending_d[tail1_q].local_wait =
              local_latency(work1_decoded.kind);
        end else if (work1_mem_launch) begin
          pending_d[tail1_q].mem = work1_mem_pending;
          pending_d[tail1_q].store_fill = work1_mem_fill;
          pending_d[tail1_q].result = work1_result;
        end
      end
      pending_count_d = after_retire_count + 3'd2;
    end
    if (abort_match) begin
      for (integer i = 0; i < PENDING_DEPTH; i++)
        if (age_of(head_q, PENDING_IDX_BITS'(i)) >= 3'(abort_index)) pending_d[i].valid = 1'b0;
      pending_count_d = 3'(abort_index);
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
    fpr_count_d = '0;
    barrier_d = 1'b0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (pending_d[i].valid) begin
        fpr_count_d += {2'd0, pending_d[i].dest_fpr};
        barrier_d |= is_barrier(pending_d[i].decoded.kind,
                                pending_d[i].decoded.op);
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      local_stage_q <= '0;
      for (integer i = 0; i < PENDING_DEPTH; i++) pending_q[i] <= '0;
      pending_count_q <= '0;
      head_q <= '0;
      head1_q <= PENDING_IDX_BITS'(1);
      tail_q <= '0;
      tail1_q <= PENDING_IDX_BITS'(1);
      fpr_count_q <= '0;
      barrier_q <= 1'b0;
      fpscr_q <= '0;
      sp_q <= '0;
      lt_q <= '0;
      deferred_abort_flush_q <= 1'b0;
      for (integer i = 0; i < 32; i++) fpr_q[i] <= '0;
    end else begin
      local_stage_q <= kill_all_i ? '0 : local_stage_d;
      for (integer i = 0; i < PENDING_DEPTH; i++) pending_q[i] <= pending_d[i];
      pending_count_q <= pending_count_d;
      head_q <= head_d;
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
           head_result.exception == FPU_FP_ENABLED)) begin
        if (head_result.fpr_write)
          fpr_q[head_result.fpr_index] <= FPR_BITS'(head_result.fpr_value);
        if (head_result.fpscr_write) fpscr_q <= head_result.fpscr_value;
      end
      if (retire1_fire && second_result.fpr_write)
        fpr_q[second_result.fpr_index] <= FPR_BITS'(second_result.fpr_value);
    end
  end

  assign inspect_fpr_o = {{(64-FPR_BITS){1'b0}},fpr_q[inspect_fpr_index_i]};
  assign inspect_fpscr_o = fpscr_q;
  assign inspect_sp_o = CPU_602 ? sp_q : 32'd0;
  assign inspect_lt_o = CPU_602 ? lt_q : 32'd0;

  // Forwarding is independent of retirement.  Two packets preserve a CR
  // result and a load FPR result that may retire together.  A CR result has
  // priority on the first bus; remaining results stay queued for a later bus.
  always_comb begin
    forward_candidate_t candidate;
    logic reply_candidate;
    ppc_fpu_arith_rsp_t ar;
    logic [31:0] candidate_fpscr;
    logic candidate_exception;
    logic arith_metadata_valid;
    logic candidate_fpr_new;
    logic candidate_cr_new;
    logic ready;
    candidate = '0;
    ar = '0;
    candidate_fpscr = '0;
    candidate_exception = 1'b0;
    arith_metadata_valid = 1'b0;
    candidate_fpr_new = 1'b0;
    candidate_cr_new = 1'b0;
    ready = 1'b0;
    reply_candidate = 1'b0;
    prefix_fpscr = fpscr_q;
    prefix_known = 1'b1;
    fwd0 = '0;
    forward_valid_o = 1'b0;
    forward_from_pending = 1'b0;
    forward_index = '0;
    fwd1 = '0;
    forward1_valid_o = 1'b0;
    forward1_from_pending = 1'b0;
    forward1_index = '0;
    for (integer i = 0; i < PENDING_DEPTH; i++) begin
      if (i < int'(pending_count_q) && pv[i].valid) begin
        ready = pv[i].done || pv[i].local_wait == 2'd1;
        reply_candidate = 1'b0;
        candidate = '0;
        candidate.tag = pv[i].issue.tag;
        candidate.fpr_index = pv[i].result.fpr_index;
        candidate.fpr_write = pv[i].result.fpr_write;
        candidate.fpr_value = pv[i].result.fpr_value;
        candidate.fpr_sp = pv[i].result.fpr_sp;
        candidate.fpr_lt = pv[i].result.fpr_lt;
        candidate.cr_write = pv[i].result.cr_write;
        candidate.cr_field = pv[i].result.cr_field;
        candidate.cr_value = pv[i].result.cr_value;
        if ((pv[i].decoded.kind == DK_MOVE ||
             pv[i].decoded.kind == DK_FSEL) && candidate.cr_write)
          candidate.cr_value = prefix_fpscr[31:28];
        candidate_exception = pv[i].result.exception != FPU_NO_EXCEPTION &&
            pv[i].result.exception != FPU_FP_ENABLED;
        if (pv[i].decoded.kind == DK_ARITH) begin
          ar = pv[i].arith;
          arith_metadata_valid = pv[i].arith_done;
          if (!ready && arith_finish_valid && pv[i].finishing) begin
            ar = arith_finish;
            ready = 1'b1;
            arith_metadata_valid = 1'b1;
            reply_candidate = 1'b1;
          end else if (!ready && arith_rsp_match &&
                       arith_rsp.tag == pv[i].issue.tag) begin
            ar = arith_rsp;
            ready = 1'b1;
            arith_metadata_valid = 1'b1;
          end
          if (arith_metadata_valid) begin
            candidate.tag = ar.tag;
            candidate.reply = reply_candidate;
            candidate.prefix = prefix_fpscr;
            candidate.fctiwz = pv[i].decoded.op == FP_FCTIWZ;
            candidate_exception = numeric_emulation_trap(ar.invalid, ar.ox,
                ar.ux, ar.zx, ar.xx, ar.tiny_before_round, prefix_fpscr[7:2]);
            candidate_fpscr = arithmetic_fpscr(prefix_fpscr, ar.invalid,
                ar.ox, ar.ux, ar.zx, ar.xx, ar.fr, ar.fi, ar.frfi_valid,
                ar.fprf, ar.fprf_valid, ar.fpcc, ar.compare_valid);
            candidate.fpr_write = (reply_candidate ? arith_finish_write :
                ar.write_result) && !candidate_exception;
            candidate.fpr_value = CPU_602 ?
                {32'd0,(pv[i].decoded.op == FP_FCTIWZ ? ar.result[31:0] :
                 narrow_single(ar.result))} : ar.result;
            candidate.fpr_sp = CPU_602 && pv[i].decoded.op != FP_FCTIWZ;
            candidate.fpr_lt = CPU_602 && pv[i].decoded.op == FP_FCTIWZ;
            candidate.cr_write = !candidate_exception &&
                (ar.compare_valid || pv[i].issue.insn[0]);
            candidate.cr_field = ar.compare_valid ?
                pv[i].issue.insn[25:23] : 3'd1;
            candidate.cr_value = ar.compare_valid ? ar.fpcc :
                candidate_fpscr[31:28];
            // A finishing result's value and status come from its reply.
            if (reply_candidate) begin
              candidate.fpr_value = '0;
              candidate.cr_value = '0;
            end
            else if (!candidate_exception) prefix_fpscr = candidate_fpscr;
          end else prefix_known = 1'b0;
        end else if (pv[i].decoded.kind == DK_MEMORY && !ready &&
                     mem_rsp_match && mem_rsp_i.tag == pv[i].issue.tag) begin
          ready = 1'b1;
          candidate_exception = mem_rsp_i.fault;
          if (pv[i].decoded.mem_load && !mem_rsp_i.fault) begin
            candidate.fpr_write = 1'b1;
            if (CPU_602) begin
              candidate.fpr_sp = 1'b1;
              candidate.fpr_value = {32'd0,mem_rsp_i.data[31:0]};
              if (!pv[i].decoded.mem_single) begin
                candidate_exception = !single_fits_double(mem_rsp_i.data);
                candidate.fpr_value = {32'd0,narrow_single(mem_rsp_i.data)};
              end
            end else candidate.fpr_value = pv[i].decoded.mem_single ?
                widen_single(mem_rsp_i.data[31:0]) : mem_rsp_i.data;
          end
        end
        candidate_fpr_new = candidate.fpr_write &&
            !pv[i].fpr_forwarded;
        candidate_cr_new = candidate.cr_write &&
            !pv[i].cr_forwarded &&
            pv[i].decoded.kind != DK_MCRFS &&
            (prefix_known || (pv[i].decoded.kind == DK_ARITH &&
                              (pv[i].decoded.op == FP_CMPU ||
                               pv[i].decoded.op == FP_CMPO)));
        if (ready && !candidate_exception &&
            (candidate_fpr_new || candidate_cr_new)) begin
          candidate.fpr_write = candidate_fpr_new;
          candidate.cr_write = candidate_cr_new;
          if (!forward_from_pending) begin
            forward_from_pending = 1'b1;
            forward_index = PENDING_IDX_BITS'(i);
            forward_valid_o = rst_ni && !kill_all_i && !abort_valid_i;
            fwd0 = candidate;
          end else if (!fwd0.cr_write && candidate_cr_new) begin
            // Promote a completed CR value without losing the displaced FPR.
            // An earlier second FPR packet remains in its queue slot.
            forward1_from_pending = forward_from_pending;
            forward1_index = forward_index;
            forward1_valid_o = forward_valid_o;
            fwd1 = fwd0;
            forward_from_pending = 1'b1;
            forward_index = PENDING_IDX_BITS'(i);
            forward_valid_o = rst_ni && !kill_all_i && !abort_valid_i;
            fwd0 = candidate;
          end else if (!forward1_from_pending) begin
            forward1_from_pending = 1'b1;
            forward1_index = PENDING_IDX_BITS'(i);
            forward1_valid_o = rst_ni && !kill_all_i && !abort_valid_i;
            fwd1 = candidate;
          end
        end
        // Younger CR results wait for a finishing result's reply.
        if (reply_candidate) prefix_known = 1'b0;
      end
    end
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
           narrow_single(arith_rsp.result))} : arith_rsp.result;
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
