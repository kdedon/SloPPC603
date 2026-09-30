// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Area-reduced FPU: the ppc_fpu interface with one instruction in flight and
// the iterative arithmetic unit. Results, FPSCR, exceptions and 602 tags match
// ppc_fpu; latencies do not follow Table 6-5. The second issue lane, second
// retirement lane and forwarding buses stay idle. The FPR inspection port
// shares the frC read and is valid except in an instruction's launch cycle.
module ppc_fpu_compact #(
    parameter bit CPU_602 = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,
    input logic issue_valid_i,
    output logic issue_ready_o,
    input ppc_fpu_pkg::ppc_fpu_issue_t issue_i,
    // The second lanes are never accepted.
    /* verilator lint_off UNUSEDSIGNAL */
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
    /* verilator lint_on UNUSEDSIGNAL */
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
    logic [63:0] raw;
    logic sp;
  } local_operand_t;
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
  typedef enum logic [1:0] {
    PH_LAUNCH, PH_ARITH, PH_MEMORY, PH_DONE
  } phase_t;
  // The issue fields kept after decode; gpr_b is mtspr data.
  typedef struct packed {
    completion_tag_t tag;
    logic [31:0] insn;
    logic [31:0] gpr_b;
    logic msr_fp;
    logic msr_fe0;
    logic msr_fe1;
    logic msr_pr;
  } held_t;

  // The held instruction. Tags, indices and addresses come from the issue
  // record; `value` holds the FPR result, store source, fault information,
  // proposed FPSCR or SPR read, by kind.
  logic busy_q;
  phase_t phase_q;
  held_t issue_q;
  decoded_t dec_q;
  logic [31:0] ea_q;
  status_t st_q;
  logic [63:0] value_q;
  arith_flags_t flags_q;
  logic arith_done_q;
  logic mem_launched_q;
  logic [31:0] fpscr_q;
  logic [31:0] sp_q;
  logic [31:0] lt_q;
  logic [31:0] written_q;

  decode_info_t issue_decode;
  logic launching;
  logic [4:0] ra_index, rb_index, rc_index;
  logic [FPR_BITS-1:0] ra_raw, rb_raw, rc_raw;
  logic [63:0] src_a, src_b, src_c;
  logic sp_a, sp_b, sp_c, lt_a, lt_b, lt_c;
  logic use_a, use_b, use_c;
  logic operand_tags_ok;
  ppc_fpu_result_t exec_result;
  ppc_fpu_result_t local_result;
  logic [31:0] proposed_fpscr;
  logic launch_arith;
  logic launch_mem;
  logic launch_local;
  ppc_fpu_result_t head_base;
  ppc_fpu_result_t head_result;
  ppc_fpu_result_t mem_result;
  logic head_live;
  logic abort_match;
  logic commit_match;
  logic retire;
  logic retire_writes;
  logic arith_rsp_take;
  logic mem_rsp_take;
  logic [63:0] load_single, load_double;
  logic load_fits;

  ppc_fpu_arith_req_t arith_req;
  ppc_fpu_arith_rsp_t arith_rsp;
  ppc_fpu_arith_rsp_t arith_finish;
  logic arith_req_valid;
  logic arith_req_ready;
  logic arith_rsp_valid;
  logic arith_finish_valid;
  logic arith_finish_write;
  logic arith_next_finish_valid;
  completion_tag_t arith_next_finish_tag;
  logic arith_div_busy;
  logic arith_flush;

  function automatic logic [31:0] normalize_fpscr(input logic [31:0] f);
    logic [31:0] n;
    n = f;
    n[29] = |{f[24:19], f[10:8]};
    n[30] = (n[29] && f[7]) || (f[28] && f[6]) ||
            (f[27] && f[5]) || (f[26] && f[4]) || (f[25] && f[3]);
    n[11] = 1'b0;
    return n;
  endfunction

  // Field extractors below read only part of their records.
  /* verilator lint_off UNUSEDSIGNAL */
  // Sticky causes OR in; FX sets on a newly set cause.
  function automatic logic [31:0] flags_fpscr(input logic [31:0] old_f,
                                              input arith_flags_t ar);
    logic [31:0] n;
    logic changed;
    n = old_f;
    for (integer i = 0; i < 6; i++) n[24-i] = old_f[24-i] | ar.invalid[i];
    for (integer i = 6; i < 9; i++) n[16-i] = old_f[16-i] | ar.invalid[i];
    n[28] = old_f[28] | ar.ox;
    n[27] = old_f[27] | ar.ux;
    n[26] = old_f[26] | ar.zx;
    n[25] = old_f[25] | ar.xx;
    if (ar.frfi_valid) begin
      n[18] = ar.fr;
      n[17] = ar.fi;
      n[25] = n[25] | ar.fi;
    end
    if (ar.compare_valid) n[15:12] = ar.fpcc;
    else if (ar.fprf_valid) n[16:12] = ar.fprf;
    changed = |(n[28:19] & ~old_f[28:19]) || |(n[10:8] & ~old_f[10:8]);
    n[31] = old_f[31] | changed;
    return normalize_fpscr(n);
  endfunction

  function automatic logic [63:0] widen_single(input logic [31:0] s);
    logic [63:0] d;
    logic [22:0] frac;
    logic [7:0] exp;
    integer lead;
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
  endfunction

  function automatic logic [31:0] narrow_single(input logic [63:0] d);
    logic [31:0] s;
    logic [52:0] sig;
    integer exponent;
    integer shift_amt;
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

  function automatic logic writes_fpr(input decode_kind_t kind,
                                      input ppc_fpu_op_t op,
                                      input logic mem_load);
    return (kind == DK_ARITH && op != FP_CMPU && op != FP_CMPO) ||
        kind == DK_MOVE || kind == DK_FSEL || kind == DK_MFFS ||
        (kind == DK_MEMORY && mem_load);
  endfunction

  // Only the 602 traps on an enabled numeric exception or, with XE clear,
  // a tiny result.
  function automatic logic flags_trap(input arith_flags_t ar,
                                      input logic [31:0] f);
    logic enabled;
    enabled = ((|ar.invalid) && f[7]) || (ar.ox && f[6]) ||
        (ar.ux && f[5]) || (ar.zx && f[4]) || (ar.xx && f[3]);
    return CPU_602 && (enabled || (!f[2] && ar.tiny_before_round));
  endfunction

  // Only the status fields of the reply are kept.
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

  // Stored format of an arithmetic result.
  function automatic logic [63:0] format_reply(input ppc_fpu_op_t op,
                                               input logic [63:0] result);
    return CPU_602 ? {32'd0, (op == FP_FCTIWZ ? result[31:0] :
        narrow_single(result))} : result;
  endfunction

  function automatic ppc_fpu_result_t numeric_result(
      input ppc_fpu_result_t base, input arith_flags_t ar,
      input logic [63:0] value,
      input ppc_fpu_op_t op, input logic rc, input logic [2:0] cr_field,
      input logic fe0, input logic fe1, input logic [31:0] old_f
  );
    ppc_fpu_result_t out;
    logic [31:0] next_f;
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
      out.cr_write = ar.compare_valid || rc;
      out.cr_field = ar.compare_valid ? cr_field : 3'd1;
      out.cr_value = ar.compare_valid ? ar.fpcc : next_f[31:28];
      if (!CPU_602 && (fe0 || fe1) && next_f[30])
        out.exception = FPU_FP_ENABLED;
    end
    return out;
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

  // D- and X-form FP loads and stores; RA is a GPR, so the first FPR
  // lookup reads frS instead.
  function automatic logic memory_form(input logic [5:0] primary);
    return primary[5:3] == 3'b110 || primary == 6'd31;
  endfunction

  // fsel takes frB when frA is a NaN or less than zero.
  function automatic logic selects_b(input logic [63:0] v);
    return CPU_602 ?
        (((v[30:23] == 8'hff) && v[22:0] != 23'd0) ||
         (v[31] && v[30:0] != 31'd0)) :
        (((v[62:52] == 11'h7ff) && v[51:0] != 52'd0) ||
         (v[63] && v[62:0] != 63'd0));
  endfunction

  function automatic ppc_fpu_result_t finish_local_data(
      input ppc_fpu_result_t base, input logic [1:0] move_kind,
      input logic is_move, input logic rc, input local_operand_t a,
      input local_operand_t b, input local_operand_t c,
      input logic c_lt);
    ppc_fpu_result_t r;
    logic choose_b;
    r = base;
    choose_b = selects_b(a.raw);
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
        if (CPU_602 && !choose_b) case ({c.sp, c_lt})
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
  endfunction

  function automatic logic [31:0] status_change(input logic [31:0] old_f,
                                                input logic [31:0] insn,
                                                input logic [63:0] b);
    logic [31:0] n;
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
  endfunction

  function automatic decode_info_t decode_packet(
      input logic [6:0] insn_hi, input logic [22:0] insn_lo,
      input logic [31:0] gpr_a, input logic [31:0] gpr_b);
    decode_info_t info;
    logic [31:0] spr;
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
        10'd535, 10'd567: begin
          info.decoded.mem_load = 1'b1;
          info.decoded.mem_single = 1'b1;
          info.decoded.mem_update = insn_lo[10:1] == 10'd567;
        end
        10'd599, 10'd631: begin
          info.decoded.mem_load = 1'b1;
          info.decoded.mem_update = insn_lo[10:1] == 10'd631;
        end
        10'd663, 10'd695: begin
          info.decoded.mem_store = 1'b1;
          info.decoded.mem_single = 1'b1;
          info.decoded.mem_update = insn_lo[10:1] == 10'd695;
        end
        10'd727, 10'd759: begin
          info.decoded.mem_store = 1'b1;
          info.decoded.mem_update = insn_lo[10:1] == 10'd759;
        end
        10'd983: begin
          info.decoded.mem_store = 1'b1;
          info.decoded.mem_integer = 1'b1;
        end
        10'd339, 10'd467: if (CPU_602 &&
            (spr == 32'd1021 || spr == 32'd1022)) begin
          info.decoded.kind = insn_lo[10:1] == 10'd339 ? DK_MFSPR : DK_MTSPR;
          info.decoded.spr_sp = spr == 32'd1021;
        end else info.decoded.kind = DK_ILLEGAL;
        default: info.decoded.kind = DK_ILLEGAL;
      endcase
    end else if (insn_hi[6:1] == 6'd59 || insn_hi[6:1] == 6'd63) begin
      info.decoded.kind = DK_ARITH;
      if (insn_hi[6:1] == 6'd59) begin
        info.decoded.single_result = 1'b1;
        case (insn_lo[5:1])
          5'd18: info.decoded.op = FP_DIV;
          5'd20: info.decoded.op = FP_SUB;
          5'd21: info.decoded.op = FP_ADD;
          5'd24: info.decoded.op = FP_FRES;
          5'd25: info.decoded.op = FP_MUL;
          5'd28: info.decoded.op = FP_MSUB;
          5'd29: info.decoded.op = FP_MADD;
          5'd30: info.decoded.op = FP_NMSUB;
          5'd31: info.decoded.op = FP_NMADD;
          default: info.decoded.kind = DK_ILLEGAL;
        endcase
      end else begin
        case (insn_lo[10:1])
          10'd0: info.decoded.op = FP_CMPU;
          10'd12: info.decoded.op = FP_FRSP;
          10'd14: info.decoded.op = FP_FCTIW;
          10'd15: info.decoded.op = FP_FCTIWZ;
          10'd32: info.decoded.op = FP_CMPO;
          10'd38, 10'd70, 10'd134, 10'd711: info.decoded.kind = DK_MTFS;
          10'd64: info.decoded.kind = DK_MCRFS;
          10'd583: info.decoded.kind = DK_MFFS;
          10'd40, 10'd72, 10'd136, 10'd264: begin
            info.decoded.kind = DK_MOVE;
            case (insn_lo[10:1])
              10'd40: info.decoded.move_kind = 2'd1;
              10'd136: info.decoded.move_kind = 2'd2;
              10'd264: info.decoded.move_kind = 2'd3;
              default: info.decoded.move_kind = 2'd0;
            endcase
          end
          default: begin
            case (insn_lo[5:1])
              5'd18: info.decoded.op = FP_DIV;
              5'd20: info.decoded.op = FP_SUB;
              5'd21: info.decoded.op = FP_ADD;
              5'd23: info.decoded.kind = DK_FSEL;
              5'd25: info.decoded.op = FP_MUL;
              5'd26: info.decoded.op = FP_FRSQRTE;
              5'd28: info.decoded.op = FP_MSUB;
              5'd29: info.decoded.op = FP_MADD;
              5'd30: info.decoded.op = FP_NMSUB;
              5'd31: info.decoded.op = FP_NMADD;
              default: info.decoded.kind = DK_ILLEGAL;
            endcase
          end
        endcase
      end
      if (info.decoded.kind == DK_ARITH) begin
        if ((info.decoded.op == FP_ADD || info.decoded.op == FP_SUB ||
             info.decoded.op == FP_DIV) && insn_lo[10:6] != 5'd0)
          info.decoded.kind = DK_ILLEGAL;
        if (info.decoded.op == FP_MUL && insn_lo[15:11] != 5'd0)
          info.decoded.kind = DK_ILLEGAL;
        if ((info.decoded.op == FP_FRES || info.decoded.op == FP_FRSQRTE ||
             info.decoded.op == FP_FRSP || info.decoded.op == FP_FCTIW ||
             info.decoded.op == FP_FCTIWZ) &&
            (insn_lo[20:16] != 5'd0 || insn_lo[10:6] != 5'd0))
          info.decoded.kind = DK_ILLEGAL;
        if ((info.decoded.op == FP_CMPU || info.decoded.op == FP_CMPO) &&
            (insn_lo[22:21] != 2'b00 || insn_lo[0]))
          info.decoded.kind = DK_ILLEGAL;
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
        10'd38, 10'd70: if (insn_lo[20:11] != 10'd0)
          info.decoded.kind = DK_ILLEGAL;
        10'd134: if (insn_lo[22:16] != 7'd0 || insn_lo[11])
          info.decoded.kind = DK_ILLEGAL;
        10'd711: if (insn_hi[0] || insn_lo[16]) info.decoded.kind = DK_ILLEGAL;
        default: info.decoded.kind = DK_ILLEGAL;
      endcase
    end
    if (info.decoded.kind == DK_MEMORY && info.decoded.mem_update &&
        insn_lo[20:16] == 5'd0)
      info.decoded.kind = DK_ILLEGAL;
    return info;
  endfunction

  // 602 double-precision arithmetic forms trap to emulation.
  function automatic logic double_trap(input decoded_t d,
                                       input logic [5:0] primary);
    return CPU_602 && d.kind == DK_ARITH &&
        (d.op == FP_FCTIW ||
         (primary == 6'd63 && d.op != FP_FCTIWZ && d.op != FP_CMPU &&
          d.op != FP_CMPO && d.op != FP_FRSP && d.op != FP_FRSQRTE));
  endfunction

  // Store source not representable as binary32 (602 double store).
  function automatic logic store_trap(input decoded_t d,
                                      input logic [30:0] s);
    return CPU_602 && d.mem_store && !d.mem_single && !d.mem_integer &&
        (s[30:23] == 8'hff || (s[30:23] == 8'd0 && s[22:0] != 23'd0));
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  assign issue_decode = decode_packet(issue_i.insn[31:25], issue_i.insn[22:0],
      issue_i.gpr_a, issue_i.gpr_b);
  assign launching = busy_q && phase_q == PH_LAUNCH;

  // Architectural FPRs: one write port, one MLAB copy per read. A register
  // not written since reset reads zero.
  assign ra_index = memory_form(issue_q.insn[31:26]) ?
      issue_q.insn[25:21] : issue_q.insn[20:16];
  assign rb_index = issue_q.insn[15:11];
  assign rc_index = launching ? issue_q.insn[10:6] : inspect_fpr_index_i;

  logic [FPR_BITS-1:0] ram_a, ram_b, ram_c;
  logic fpr_we;
  logic [4:0] fpr_waddr;
  logic [FPR_BITS-1:0] fpr_wdata;
  ppc_ram_lut #(.DEPTH(32), .WIDTH(FPR_BITS)) fpr_a (
    .clk_i, .we_i(rst_ni && fpr_we), .waddr_i(fpr_waddr), .wdata_i(fpr_wdata),
    .raddr_i(ra_index), .rdata_o(ram_a));
  ppc_ram_lut #(.DEPTH(32), .WIDTH(FPR_BITS)) fpr_b (
    .clk_i, .we_i(rst_ni && fpr_we), .waddr_i(fpr_waddr), .wdata_i(fpr_wdata),
    .raddr_i(rb_index), .rdata_o(ram_b));
  ppc_ram_lut #(.DEPTH(32), .WIDTH(FPR_BITS)) fpr_c (
    .clk_i, .we_i(rst_ni && fpr_we), .waddr_i(fpr_waddr), .wdata_i(fpr_wdata),
    .raddr_i(rc_index), .rdata_o(ram_c));
  assign ra_raw = written_q[ra_index] ? ram_a : '0;
  assign rb_raw = written_q[rb_index] ? ram_b : '0;
  assign rc_raw = written_q[rc_index] ? ram_c : '0;
  assign src_a = 64'(ra_raw);
  assign src_b = 64'(rb_raw);
  assign src_c = 64'(rc_raw);
  assign sp_a = CPU_602 && sp_q[31-ra_index];
  assign sp_b = CPU_602 && sp_q[31-rb_index];
  assign sp_c = CPU_602 && sp_q[31-rc_index];
  assign lt_a = CPU_602 && lt_q[31-ra_index];
  assign lt_b = CPU_602 && lt_q[31-rb_index];
  assign lt_c = CPU_602 && lt_q[31-rc_index];

  // Launch: exceptions, local results and resource requests.
  always_comb begin
    local_operand_t la, lb, lc;
    use_a = 1'b0;
    use_b = 1'b0;
    use_c = 1'b0;
    if (dec_q.kind == DK_ARITH) begin
      use_a = !(dec_q.op == FP_FRSP || dec_q.op == FP_FCTIW ||
          dec_q.op == FP_FCTIWZ || dec_q.op == FP_FRES ||
          dec_q.op == FP_FRSQRTE);
      use_b = dec_q.op != FP_MUL;
      use_c = dec_q.op == FP_MUL || dec_q.op == FP_MADD ||
          dec_q.op == FP_MSUB || dec_q.op == FP_NMADD ||
          dec_q.op == FP_NMSUB;
    end
    operand_tags_ok = 1'b1;
    if (CPU_602) begin
      if (dec_q.kind == DK_ARITH) begin
        if (use_a && !sp_a) operand_tags_ok = 1'b0;
        if (use_b && !sp_b) operand_tags_ok = 1'b0;
        if (use_c && !sp_c) operand_tags_ok = 1'b0;
      end
      if (dec_q.kind == DK_MTFS && issue_q.insn[10:1] == 10'd711)
        operand_tags_ok = lt_b;
      if (dec_q.kind == DK_MEMORY && dec_q.mem_store)
        operand_tags_ok = dec_q.mem_integer ? lt_a : sp_a;
    end
    exec_result = '0;
    exec_result.tag = issue_q.tag;
    exec_result.ea = ea_q;
    exec_result.fpr_index = issue_q.insn[25:21];
    exec_result.gpr_index = issue_q.insn[20:16];
    exec_result.gpr_value = ea_q;
    exec_result.gpr_update = dec_q.kind == DK_MEMORY && dec_q.mem_update;
    exec_result.cr_field = issue_q.insn[25:23];
    proposed_fpscr = status_change(fpscr_q, issue_q.insn, src_b);
    if (dec_q.kind == DK_ILLEGAL) begin
      exec_result.exception = FPU_ILLEGAL;
      exec_result.gpr_update = 1'b0;
    end else if ((dec_q.kind == DK_MFSPR || dec_q.kind == DK_MTSPR) &&
                 issue_q.msr_pr) begin
      exec_result.exception = FPU_PRIVILEGED;
      exec_result.gpr_update = 1'b0;
    end else if (!issue_q.msr_fp && dec_q.kind != DK_MFSPR &&
                 dec_q.kind != DK_MTSPR) begin
      exec_result.exception = FPU_UNAVAILABLE;
      exec_result.gpr_update = 1'b0;
    end else if (double_trap(dec_q, issue_q.insn[31:26])) begin
      exec_result.exception = FPU_EMULATION_TRAP;
    end else if (!operand_tags_ok && dec_q.kind != DK_MOVE &&
                 dec_q.kind != DK_FSEL) begin
      exec_result.exception = CPU_602 ? FPU_EMULATION_TRAP : FPU_ILLEGAL;
      exec_result.gpr_update = 1'b0;
    end else begin
      case (dec_q.kind)
        DK_MFFS: begin
          exec_result.fpr_write = 1'b1;
          exec_result.fpr_value = {32'd0, fpscr_q};
          exec_result.fpr_lt = CPU_602;
          exec_result.cr_write = issue_q.insn[0];
          exec_result.cr_field = 3'd1;
          exec_result.cr_value = fpscr_q[31:28];
        end
        DK_MCRFS: begin
          exec_result.fpscr_write = 1'b1;
          exec_result.fpscr_value = proposed_fpscr;
          exec_result.cr_write = 1'b1;
          exec_result.cr_field = issue_q.insn[25:23];
          exec_result.cr_value = fpscr_q[31-4*int'(issue_q.insn[20:18]) -: 4];
        end
        DK_MTFS: begin
          exec_result.fpscr_write = 1'b1;
          exec_result.fpscr_value = proposed_fpscr;
          exec_result.cr_write = issue_q.insn[0];
          exec_result.cr_field = 3'd1;
          exec_result.cr_value = proposed_fpscr[31:28];
          if ((issue_q.msr_fe0 || issue_q.msr_fe1) && proposed_fpscr[30])
            exec_result.exception = FPU_FP_ENABLED;
        end
        DK_MFSPR: begin
          exec_result.gpr_update = 1'b1;
          exec_result.gpr_index = issue_q.insn[25:21];
          exec_result.gpr_value = dec_q.spr_sp ? sp_q : lt_q;
        end
        DK_MEMORY: begin
          if (ea_q[1:0] != 2'b00 && (!CPU_602 || dec_q.mem_store)) begin
            exec_result.exception = FPU_ALIGNMENT;
            exec_result.gpr_update = 1'b0;
          end else if (store_trap(dec_q, src_a[30:0])) begin
            exec_result.exception = FPU_EMULATION_TRAP;
            exec_result.gpr_update = 1'b0;
          end else exec_result.store = dec_q.mem_store;
        end
        default: ;
      endcase
    end
    la.raw = src_a;
    la.sp = sp_a;
    lb.raw = src_b;
    lb.sp = sp_b;
    lc.raw = src_c;
    lc.sp = sp_c;
    local_result = exec_result;
    if (dec_q.kind == DK_MOVE || dec_q.kind == DK_FSEL)
      local_result = finish_local_data(exec_result, dec_q.move_kind,
          dec_q.kind == DK_MOVE, issue_q.insn[0], la, lb, lc, lt_c);
    launch_arith = exec_result.exception == FPU_NO_EXCEPTION &&
        dec_q.kind == DK_ARITH;
    launch_mem = exec_result.exception == FPU_NO_EXCEPTION &&
        dec_q.kind == DK_MEMORY;
    launch_local = !launch_arith && !launch_mem;
  end

  always_comb begin
    arith_req = '0;
    arith_req.tag = issue_q.tag;
    arith_req.op = dec_q.op;
    arith_req.a = CPU_602 ? widen_single(src_a[31:0]) : src_a;
    arith_req.b = CPU_602 ? widen_single(src_b[31:0]) : src_b;
    arith_req.c = CPU_602 ? widen_single(src_c[31:0]) : src_c;
    arith_req.rn = fpscr_q[1:0];
    arith_req.ni = fpscr_q[2];
    arith_req.ve = fpscr_q[7];
    arith_req.oe = fpscr_q[6];
    arith_req.ue = fpscr_q[5];
    arith_req.ze = fpscr_q[4];
    arith_req.single_result = dec_q.single_result;
  end

  assign abort_match = abort_valid_i && busy_q && abort_tag_i == issue_q.tag;
  assign arith_req_valid = rst_ni && !kill_all_i && !abort_match &&
      launching && launch_arith;
  assign arith_flush = kill_all_i || abort_match;

  ppc_fpu_arith_compact #(.CPU_602(CPU_602)) arithmetic (
    .clk_i, .rst_ni,
    .req_valid_i(arith_req_valid), .req_ready_o(arith_req_ready),
    .req_i(arith_req),
    .req_fwd_i(3'b000),
    .rsp_valid_o(arith_rsp_valid),
    .rsp_ready_i(1'b1), .rsp_o(arith_rsp),
    .finish_valid_o(arith_finish_valid), .finish_o(arith_finish),
    .finish_write_o(arith_finish_write),
    .next_finish_valid_o(arith_next_finish_valid),
    .next_finish_tag_o(arith_next_finish_tag),
    .div_busy_o(arith_div_busy),
    .flush_i(arith_flush)
  );
  // The finish bypass and credit outputs serve pipelined shells.
  logic unused_finish;
  assign unused_finish = ^{arith_finish_valid, arith_finish, arith_finish_write,
      arith_next_finish_valid, arith_next_finish_tag, arith_div_busy};

  // Memory preparation.
  always_comb begin
    mem_req_o = '0;
    mem_req_o.tag = issue_q.tag;
    mem_req_o.ea = ea_q;
    mem_req_o.size_bytes = (dec_q.mem_single || dec_q.mem_integer) ?
        4'd4 : 4'd8;
    mem_req_o.write = dec_q.mem_store;
    mem_req_valid_o = rst_ni && !kill_all_i && !abort_match &&
        launching && launch_mem;
    // A reply for the launching instruction waits until its request is
    // registered; stale replies drain.
    mem_rsp_ready_o = rst_ni && !kill_all_i &&
        !(launching && mem_rsp_i.tag == issue_q.tag);
  end

  always_comb begin
    logic [31:0] narrowed;
    narrowed = narrow_single(mem_rsp_i.data);
    load_single = CPU_602 ? {32'd0, mem_rsp_i.data[31:0]} :
        widen_single(mem_rsp_i.data[31:0]);
    load_double = CPU_602 ? {32'd0, narrowed} : mem_rsp_i.data;
    load_fits = !CPU_602 || (mem_rsp_i.data[62:52] != 11'h7ff &&
        (narrowed[30:23] != 8'd0 || narrowed[22:0] == 23'd0) &&
        widen_single(narrowed) == mem_rsp_i.data);
  end

  assign arith_rsp_take = busy_q && phase_q == PH_ARITH && arith_rsp_valid &&
      arith_rsp.tag == issue_q.tag;
  assign mem_rsp_take = busy_q && phase_q == PH_MEMORY && mem_rsp_valid_i &&
      mem_rsp_ready_o && mem_rsp_i.tag == issue_q.tag;

  // Result view of the held instruction.
  always_comb begin
    logic spr_read;
    spr_read = CPU_602 && dec_q.kind == DK_MFSPR;
    head_base = '0;
    head_base.tag = issue_q.tag;
    head_base.exception = st_q.exception;
    head_base.ea = ea_q;
    head_base.fault_code = st_q.fault_code;
    head_base.fault_info = st_q.exception == FPU_MEMORY_FAULT ?
        value_q[31:0] : '0;
    head_base.fpr_index = issue_q.insn[25:21];
    head_base.fpr_write = st_q.fpr_write;
    head_base.fpr_value = st_q.fpr_write ? value_q : '0;
    head_base.fpr_sp = st_q.fpr_sp;
    head_base.fpr_lt = st_q.fpr_lt;
    head_base.fpscr_write = st_q.fpscr_write;
    head_base.fpscr_value = st_q.fpscr_write ? value_q[31:0] : '0;
    head_base.cr_write = st_q.cr_write;
    head_base.cr_field = st_q.cr_field;
    head_base.cr_value = st_q.cr_value;
    head_base.gpr_update = st_q.gpr_update;
    head_base.gpr_index = spr_read ? issue_q.insn[25:21] : issue_q.insn[20:16];
    head_base.gpr_value = spr_read ? value_q[31:0] : ea_q;
    head_base.store = st_q.store;
    head_result = head_base;
    if ((dec_q.kind == DK_MOVE || dec_q.kind == DK_FSEL) &&
        head_result.cr_write)
      head_result.cr_value = fpscr_q[31:28];
    if (dec_q.kind == DK_ARITH && arith_done_q)
      head_result = numeric_result(head_base, flags_q, value_q, dec_q.op,
          issue_q.insn[0], issue_q.insn[25:23], issue_q.msr_fe0,
          issue_q.msr_fe1, fpscr_q);
    // An arriving load or preparation reply.
    mem_result = head_base;
    if (mem_rsp_i.fault) begin
      mem_result.exception = FPU_MEMORY_FAULT;
      mem_result.fault_code = mem_rsp_i.fault_code;
      mem_result.fault_info = mem_rsp_i.fault_info;
      mem_result.gpr_update = 1'b0;
      mem_result.store = 1'b0;
    end else if (dec_q.mem_load) begin
      mem_result.fpr_write = 1'b1;
      mem_result.fpr_value = dec_q.mem_single ? load_single : load_double;
      mem_result.fpr_sp = CPU_602;
      if (!dec_q.mem_single && !load_fits) begin
        mem_result.exception = FPU_EMULATION_TRAP;
        mem_result.fpr_write = 1'b0;
        mem_result.fpr_value = '0;
        mem_result.gpr_update = 1'b0;
      end
    end
  end

  assign head_live = busy_q && phase_q == PH_DONE;
  assign result_valid_o = rst_ni && !kill_all_i && !abort_match && head_live;
  assign result_o = head_result;
  assign result1_valid_o = 1'b0;
  assign result1_o = '0;

  always_comb begin
    store_o = '0;
    if (mem_launched_q && dec_q.mem_store) begin
      store_o.tag = issue_q.tag;
      store_o.ea = ea_q;
      store_o.size_bytes = (dec_q.mem_single || dec_q.mem_integer) ?
          4'd4 : 4'd8;
      store_o.write = 1'b1;
      store_o.data = store_data(dec_q.mem_integer, dec_q.mem_single, value_q);
    end
  end

  // Commit and issue handshakes are separate processes: results never
  // depend on them.
  assign commit_match = head_live && commit_valid_i &&
      commit_tag_i == issue_q.tag;
  assign store_valid_o = result_valid_o && head_result.store && commit_match;
  assign commit_ready_o = result_valid_o && commit_match &&
      (!head_result.store || store_ready_i);
  assign commit1_ready_o = 1'b0;
  assign retire = commit_ready_o;
  assign retire_writes = retire &&
      (head_result.exception == FPU_NO_EXCEPTION ||
       head_result.exception == FPU_FP_ENABLED);
  assign issue_ready_o = rst_ni && !kill_all_i && !abort_valid_i && !busy_q;
  assign issue1_ready_o = 1'b0;

  assign fpr_we = retire_writes && head_result.fpr_write;
  assign fpr_waddr = head_result.fpr_index;
  assign fpr_wdata = FPR_BITS'(head_result.fpr_value);

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      busy_q <= 1'b0;
      phase_q <= PH_LAUNCH;
      arith_done_q <= 1'b0;
      mem_launched_q <= 1'b0;
      fpscr_q <= '0;
      sp_q <= '0;
      lt_q <= '0;
      written_q <= '0;
    end else begin
      if (issue_valid_i && issue_ready_o) begin
        busy_q <= 1'b1;
        phase_q <= PH_LAUNCH;
        issue_q.tag <= issue_i.tag;
        issue_q.insn <= issue_i.insn;
        issue_q.gpr_b <= CPU_602 ? issue_i.gpr_b : 32'd0;
        issue_q.msr_fp <= issue_i.msr_fp;
        issue_q.msr_fe0 <= issue_i.msr_fe0;
        issue_q.msr_fe1 <= issue_i.msr_fe1;
        issue_q.msr_pr <= issue_i.msr_pr;
        dec_q <= issue_decode.decoded;
        ea_q <= issue_decode.ea;
        arith_done_q <= 1'b0;
        mem_launched_q <= 1'b0;
      end
      if (launching) begin
        st_q <= status_of(local_result);
        if (launch_local) begin
          value_q <= value_of(dec_q.kind, local_result);
          phase_q <= PH_DONE;
        end else if (launch_arith && arith_req_ready) begin
          phase_q <= PH_ARITH;
        end else if (launch_mem && mem_req_ready_i) begin
          value_q <= src_a;
          mem_launched_q <= 1'b1;
          phase_q <= PH_MEMORY;
        end
      end
      if (arith_rsp_take) begin
        flags_q <= flags_of(arith_rsp);
        arith_done_q <= 1'b1;
        phase_q <= PH_DONE;
        if (flags_trap(flags_of(arith_rsp), fpscr_q))
          st_q.exception <= FPU_EMULATION_TRAP;
        else begin
          st_q.fpr_write <= arith_rsp.write_result;
          st_q.fpr_sp <= CPU_602 && dec_q.op != FP_FCTIWZ;
          st_q.fpr_lt <= CPU_602 && dec_q.op == FP_FCTIWZ;
          value_q <= format_reply(dec_q.op, arith_rsp.result);
        end
      end
      if (mem_rsp_take) begin
        st_q <= status_of(mem_result);
        if (mem_rsp_i.fault || dec_q.mem_load)
          value_q <= value_of(DK_MEMORY, mem_result);
        phase_q <= PH_DONE;
      end
      if (retire || abort_match || kill_all_i) busy_q <= 1'b0;
      if (retire_writes) begin
        if (head_result.fpscr_write) fpscr_q <= head_result.fpscr_value;
        if (head_result.fpr_write) written_q[head_result.fpr_index] <= 1'b1;
        if (CPU_602 && head_result.fpr_write) begin
          sp_q[31-head_result.fpr_index] <= head_result.fpr_sp;
          lt_q[31-head_result.fpr_index] <= head_result.fpr_lt;
        end
        if (CPU_602 && dec_q.kind == DK_MTSPR) begin
          if (dec_q.spr_sp) sp_q <= issue_q.gpr_b;
          else lt_q <= issue_q.gpr_b;
        end
      end
    end
  end

  assign inspect_fpr_o = src_c;
  assign inspect_fpscr_o = fpscr_q;
  assign inspect_sp_o = CPU_602 ? sp_q : 32'd0;
  assign inspect_lt_o = CPU_602 ? lt_q : 32'd0;
  assign forward_valid_o = 1'b0;
  assign forward_o = '0;
  assign forward1_valid_o = 1'b0;
  assign forward1_o = '0;
  assign forward_data_o = '0;
  assign forward1_data_o = '0;
endmodule
`default_nettype wire
