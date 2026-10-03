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
  import ppc_fpu_shell_pkg::*;
  import ppc_fpu_arith_pkg::operand_602;
  import ppc_fpu_arith_pkg::word_602;
  import ppc_fpu_arith_pkg::fits_602;

  localparam int FPR_BITS = CPU_602 ? 32 : 64;

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
    logic le_align;
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

  // Field extractors below read only part of their records.
  /* verilator lint_off UNUSEDSIGNAL */
  // Stored format of an arithmetic result.
  function automatic logic [63:0] format_reply(input ppc_fpu_op_t op,
                                               input logic [63:0] result);
    return CPU_602 ? {32'd0, (op == FP_FCTIWZ ? result[31:0] :
        word_602(result))} : result;
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
        stfd_traps(s);
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  assign issue_decode = decode_packet(CPU_602, issue_i.insn[31:25],
      issue_i.insn[22:0], issue_i.gpr_a, issue_i.gpr_b);
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
          if ((ea_q[1:0] != 2'b00 && (!CPU_602 || dec_q.mem_store)) ||
              le_misaligned(issue_q.le_align, ea_q[2:0],
                            !dec_q.mem_single && !dec_q.mem_integer)) begin
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
      local_result = finish_local_data(CPU_602, exec_result, dec_q.move_kind,
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
    arith_req.a = CPU_602 ? operand_602(src_a[31:0]) : src_a;
    arith_req.b = CPU_602 ? operand_602(src_b[31:0]) : src_b;
    arith_req.c = CPU_602 ? operand_602(src_c[31:0]) : src_c;
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
    .rsp_held_o(arith_rsp_held),
    .rsp_ready_i(1'b1), .rsp_o(arith_rsp),
    .finish_valid_o(arith_finish_valid), .finish_o(arith_finish),
    .finish_write_o(arith_finish_write),
    .next_finish_valid_o(arith_next_finish_valid),
    .next_finish_tag_o(arith_next_finish_tag),
    .div_busy_o(arith_div_busy),
    .flush_i(arith_flush)
  );
  // The finish bypass and credit outputs serve pipelined shells.
  logic arith_rsp_held;
  logic unused_finish;
  assign unused_finish = ^{arith_finish_valid, arith_finish, arith_finish_write,
      arith_next_finish_valid, arith_next_finish_tag, arith_div_busy,
      arith_rsp_held};

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
    load_single = CPU_602 ? {32'd0, mem_rsp_i.data[31:0]} :
        widen_single(mem_rsp_i.data[31:0]);
    load_double = CPU_602 ? {32'd0, word_602(mem_rsp_i.data)} :
        mem_rsp_i.data;
    load_fits = !CPU_602 || fits_602(mem_rsp_i.data[62:0]);
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
      head_result = numeric_result(CPU_602, head_base, flags_q, value_q,
          dec_q.op, issue_q.insn[0], issue_q.insn[25:23], issue_q.msr_fe0,
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
      store_o.data = store_data(CPU_602, dec_q.mem_integer, dec_q.mem_single,
          value_q);
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
        issue_q.le_align <= issue_i.le_align;
        dec_q <= issue_decode.decoded;
        ea_q <= issue_decode.ea;
        arith_done_q <= 1'b0;
        mem_launched_q <= 1'b0;
      end
      if (launching) begin
        st_q <= status_of(local_result);
        if (launch_local) begin
          value_q <= value_of(CPU_602, dec_q.kind, local_result);
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
        if (flags_trap(CPU_602, flags_of(arith_rsp), fpscr_q))
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
          value_q <= value_of(CPU_602, DK_MEMORY, mem_result);
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
