`default_nettype none
module ppc_fpu (
    input logic clk_i,
    input logic rst_ni,
    input logic issue_valid_i,
    output logic issue_ready_o,
    input ppc_fpu_pkg::ppc_fpu_issue_t issue_i,
    output logic result_valid_o,
    output ppc_fpu_pkg::ppc_fpu_result_t result_o,
    input logic commit_valid_i,
    input ppc_pkg::completion_tag_t commit_tag_i,
    output logic commit_ready_o,
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
    output logic [31:0] inspect_fpscr_o
);
  import ppc_pkg::completion_tag_t;
  import ppc_fpu_pkg::*;

  typedef enum logic [2:0] {
    IDLE, SEND_ARITH, WAIT_ARITH, SEND_MEM, WAIT_MEM, READY
  } state_t;
  typedef enum logic [2:0] {
    DK_ILLEGAL, DK_ARITH, DK_MOVE, DK_FSEL, DK_MFFS, DK_MCRFS,
    DK_MTFS, DK_MEMORY
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
  } decoded_t;

  state_t state_q;
  decoded_t decoded;
  ppc_fpu_result_t held_q;
  logic issue_rc_q;
  logic issue_fe_any_q;
  ppc_fpu_mem_t mem_q;
  ppc_fpu_arith_req_t arith_req_q;
  ppc_fpu_arith_rsp_t arith_rsp;
  logic arith_req_ready;
  logic arith_rsp_valid;
  logic [63:0] fpr_q [0:31];
  logic [31:0] fpscr_q;
  logic [31:0] proposed_fpscr;
  logic [31:0] arith_fpscr_next;
  logic [31:0] issue_ea;
  logic [63:0] issue_b;
  logic [63:0] issue_a;
  logic [63:0] issue_c;
  logic commit_match;
  logic abort_match;
  logic pending_match_mem;
  logic pending_match_arith;
  logic fp_opcode_class;

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
        d[51:0] = (52'(frac) << (52 - lead));
      end
      return d;
    end
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
      if (exponent == 2047) begin
        s[30:23] = 8'hff;
        s[22:0] = d[51:29];
      end else if (exponent >= 897) begin
        s[30:23] = 8'(exponent - 896);
        s[22:0] = d[51:29];
      end else if (exponent != 0) begin
        sig = {1'b1, d[51:0]};
        shift_amt = 29 + (897 - exponent);
        if (shift_amt < 53) s[22:0] = 23'(sig >> shift_amt);
      end
      return s;
    end
  endfunction

  always_comb begin
    decoded = '0;
    decoded.kind = DK_ILLEGAL;
    fp_opcode_class = (issue_i.insn[31:26] == 6'd59) ||
                      (issue_i.insn[31:26] == 6'd63) ||
                      (issue_i.insn[31:26] >= 6'd48 && issue_i.insn[31:26] <= 6'd55);
    issue_ea = 32'd0;
    if (issue_i.insn[31:26] >= 6'd48 && issue_i.insn[31:26] <= 6'd55) begin
      decoded.kind = DK_MEMORY;
      decoded.mem_load = (issue_i.insn[31:26] <= 6'd51);
      decoded.mem_store = !decoded.mem_load;
      decoded.mem_single = (issue_i.insn[31:26] == 6'd48) ||
                           (issue_i.insn[31:26] == 6'd49) ||
                           (issue_i.insn[31:26] == 6'd52) ||
                           (issue_i.insn[31:26] == 6'd53);
      decoded.mem_update = issue_i.insn[26];
      issue_ea = (issue_i.insn[20:16] == 5'd0 ? 32'd0 : issue_i.gpr_a) +
                 {{16{issue_i.insn[15]}}, issue_i.insn[15:0]};
    end else if (issue_i.insn[31:26] == 6'd31 && issue_i.insn[0] == 1'b0) begin
      decoded.kind = DK_MEMORY;
      issue_ea = (issue_i.insn[20:16] == 5'd0 ? 32'd0 : issue_i.gpr_a) + issue_i.gpr_b;
      case (issue_i.insn[10:1])
        10'd535, 10'd567: begin decoded.mem_load=1'b1; decoded.mem_single=1'b1; decoded.mem_update=(issue_i.insn[10:1]==10'd567); end
        10'd599, 10'd631: begin decoded.mem_load=1'b1; decoded.mem_update=(issue_i.insn[10:1]==10'd631); end
        10'd663, 10'd695: begin decoded.mem_store=1'b1; decoded.mem_single=1'b1; decoded.mem_update=(issue_i.insn[10:1]==10'd695); end
        10'd727, 10'd759: begin decoded.mem_store=1'b1; decoded.mem_update=(issue_i.insn[10:1]==10'd759); end
        10'd983: begin decoded.mem_store=1'b1; decoded.mem_integer=1'b1; end
        default: decoded.kind=DK_ILLEGAL;
      endcase
      if (decoded.kind == DK_MEMORY) fp_opcode_class = 1'b1;
    end else if (issue_i.insn[31:26] == 6'd59 || issue_i.insn[31:26] == 6'd63) begin
      decoded.kind = DK_ARITH;
      case (issue_i.insn[31:26])
        6'd59: begin
          decoded.single_result = 1'b1;
          case (issue_i.insn[5:1])
            5'd18: decoded.op=FP_DIV;
            5'd20: decoded.op=FP_SUB;
            5'd21: decoded.op=FP_ADD;
            5'd24: decoded.op=FP_FRES;
            5'd25: decoded.op=FP_MUL;
            5'd28: decoded.op=FP_MSUB;
            5'd29: decoded.op=FP_MADD;
            5'd30: decoded.op=FP_NMSUB;
            5'd31: decoded.op=FP_NMADD;
            default: decoded.kind=DK_ILLEGAL;
          endcase
        end
        default: begin
          case (issue_i.insn[10:1])
            10'd0: decoded.op=FP_CMPU;
            10'd12: decoded.op=FP_FRSP;
            10'd14: decoded.op=FP_FCTIW;
            10'd15: decoded.op=FP_FCTIWZ;
            10'd32: decoded.op=FP_CMPO;
            10'd38,10'd70,10'd134,10'd711: decoded.kind=DK_MTFS;
            10'd64: decoded.kind=DK_MCRFS;
            10'd583: decoded.kind=DK_MFFS;
            10'd40,10'd72,10'd136,10'd264: begin
              decoded.kind=DK_MOVE;
              case (issue_i.insn[10:1])
                10'd40: decoded.move_kind=2'd1;
                10'd136: decoded.move_kind=2'd2;
                10'd264: decoded.move_kind=2'd3;
                default: decoded.move_kind=2'd0;
              endcase
            end
            default: begin
              case (issue_i.insn[5:1])
                5'd18: decoded.op=FP_DIV;
                5'd20: decoded.op=FP_SUB;
                5'd21: decoded.op=FP_ADD;
                5'd23: decoded.kind=DK_FSEL;
                5'd25: decoded.op=FP_MUL;
                5'd26: decoded.op=FP_FRSQRTE;
                5'd28: decoded.op=FP_MSUB;
                5'd29: decoded.op=FP_MADD;
                5'd30: decoded.op=FP_NMSUB;
                5'd31: decoded.op=FP_NMADD;
                default: decoded.kind=DK_ILLEGAL;
              endcase
            end
          endcase
        end
      endcase
      if (decoded.kind == DK_ARITH) begin
        if ((decoded.op == FP_ADD || decoded.op == FP_SUB || decoded.op == FP_DIV) &&
            issue_i.insn[10:6] != 5'd0) decoded.kind=DK_ILLEGAL;
        if (decoded.op == FP_MUL && issue_i.insn[15:11] != 5'd0) decoded.kind=DK_ILLEGAL;
        if ((decoded.op == FP_FRES || decoded.op == FP_FRSQRTE ||
             decoded.op == FP_FRSP || decoded.op == FP_FCTIW ||
             decoded.op == FP_FCTIWZ) &&
            (issue_i.insn[20:16] != 5'd0 || issue_i.insn[10:6] != 5'd0)) decoded.kind=DK_ILLEGAL;
        if ((decoded.op == FP_CMPU || decoded.op == FP_CMPO) &&
            (issue_i.insn[22:21] != 2'b00 || issue_i.insn[0]))
          decoded.kind=DK_ILLEGAL;
      end
    end
    if (decoded.kind == DK_MOVE && issue_i.insn[20:16] != 5'd0)
      decoded.kind = DK_ILLEGAL;
    if (decoded.kind == DK_MFFS && issue_i.insn[20:11] != 10'd0)
      decoded.kind = DK_ILLEGAL;
    if (decoded.kind == DK_MCRFS &&
        (issue_i.insn[22:21] != 2'b00 || issue_i.insn[17:11] != 7'd0 || issue_i.insn[0]))
      decoded.kind = DK_ILLEGAL;
    if (decoded.kind == DK_MTFS) begin
      case (issue_i.insn[10:1])
        10'd38, 10'd70: if (issue_i.insn[20:11] != 10'd0) decoded.kind=DK_ILLEGAL;
        10'd134: if (issue_i.insn[22:16] != 7'd0 || issue_i.insn[11])
                    decoded.kind=DK_ILLEGAL;
        10'd711: if (issue_i.insn[25] || issue_i.insn[16]) decoded.kind=DK_ILLEGAL;
        default: decoded.kind=DK_ILLEGAL;
      endcase
    end
    if (decoded.kind == DK_MEMORY && decoded.mem_update && issue_i.insn[20:16] == 5'd0)
      decoded.kind = DK_ILLEGAL;
  end

  assign issue_a = fpr_q[issue_i.insn[20:16]];
  assign issue_b = fpr_q[issue_i.insn[15:11]];
  assign issue_c = fpr_q[issue_i.insn[10:6]];
  assign inspect_fpr_o = fpr_q[inspect_fpr_index_i];
  assign inspect_fpscr_o = fpscr_q;
  assign issue_ready_o = (rst_ni && state_q == IDLE && !kill_all_i);
  assign result_valid_o = (rst_ni && state_q == READY);
  assign result_o = held_q;
  assign commit_match = commit_valid_i && (commit_tag_i == held_q.tag);
  assign abort_match = abort_valid_i && (abort_tag_i == held_q.tag);
  assign pending_match_mem = mem_rsp_i.tag == held_q.tag;
  assign pending_match_arith = arith_rsp.tag == held_q.tag;
  assign arith_fpscr_next = arithmetic_fpscr(
      fpscr_q, arith_rsp.invalid, arith_rsp.ox, arith_rsp.ux, arith_rsp.zx,
      arith_rsp.xx, arith_rsp.fr, arith_rsp.fi, arith_rsp.frfi_valid,
      arith_rsp.fprf, arith_rsp.fprf_valid, arith_rsp.fpcc, arith_rsp.compare_valid);
  assign mem_req_valid_o = (rst_ni && state_q == SEND_MEM && !kill_all_i && !abort_match);
  assign mem_req_o = mem_q;
  // A combinational LSU reply must wait until its request has been accepted.
  // Stale replies still drain while this instruction prepares its request.
  assign mem_rsp_ready_o = !(state_q == SEND_MEM && pending_match_mem);
  assign store_valid_o = (rst_ni && state_q == READY && held_q.store && commit_match &&
                          !kill_all_i && !abort_match);
  assign store_o = mem_q;
  assign commit_ready_o = (rst_ni && state_q == READY && commit_match && !kill_all_i &&
                           !abort_match && (!held_q.store || store_ready_i));

  ppc_fpu_arith arithmetic (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .req_valid_i(state_q == SEND_ARITH && !kill_all_i && !abort_match),
      .req_ready_o(arith_req_ready), .req_i(arith_req_q),
      .rsp_valid_o(arith_rsp_valid), .rsp_ready_i(state_q == WAIT_ARITH), .rsp_o(arith_rsp),
      .flush_i(kill_all_i || abort_match)
  );

  always_comb begin
    proposed_fpscr = fpscr_q;
    case (issue_i.insn[10:1])
      10'd38: if (issue_i.insn[25:21] != 5'd1 && issue_i.insn[25:21] != 5'd2) begin
        proposed_fpscr[31-issue_i.insn[25:21]] = 1'b1;
        if (!fpscr_q[31-issue_i.insn[25:21]] &&
            ((issue_i.insn[25:21] >= 5'd3 && issue_i.insn[25:21] <= 5'd12) ||
             (issue_i.insn[25:21] >= 5'd21 && issue_i.insn[25:21] <= 5'd23)))
          proposed_fpscr[31] = 1'b1;
      end
      10'd70: if (issue_i.insn[25:21] != 5'd1 && issue_i.insn[25:21] != 5'd2)
        proposed_fpscr[31-issue_i.insn[25:21]] = 1'b0;
      10'd134: proposed_fpscr[31-4*int'(issue_i.insn[25:23]) -: 4] = issue_i.insn[15:12];
      10'd711: for (integer i = 0; i < 8; i++) begin
        if (issue_i.insn[24-i]) proposed_fpscr[31-4*i -: 4] = issue_b[31-4*i -: 4];
      end
      default: proposed_fpscr = fpscr_q;
    endcase
    if (issue_i.insn[10:1] == 10'd64) begin
      case (issue_i.insn[20:18])
        3'd0: proposed_fpscr[31:28] = 4'b0000;
        3'd1: proposed_fpscr[27:24] = 4'b0000;
        3'd2: proposed_fpscr[23:20] = 4'b0000;
        3'd3: proposed_fpscr[19] = 1'b0;
        3'd5: proposed_fpscr[10:8] = 3'b000;
        default: proposed_fpscr = fpscr_q;
      endcase
    end
    proposed_fpscr = normalize_fpscr(proposed_fpscr);
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      held_q <= '0;
      issue_rc_q <= 1'b0;
      issue_fe_any_q <= 1'b0;
      mem_q <= '0;
      arith_req_q <= '0;
      fpscr_q <= 32'd0;
    end else if (kill_all_i || (abort_match && state_q != IDLE)) begin
      state_q <= IDLE;
    end else begin
      case (state_q)
        IDLE: if (issue_valid_i) begin
          issue_rc_q <= issue_i.insn[0];
          issue_fe_any_q <= issue_i.msr_fe0 || issue_i.msr_fe1;
          held_q <= '0;
          held_q.tag <= issue_i.tag;
          held_q.fpr_index <= issue_i.insn[25:21];
          held_q.cr_field <= issue_i.insn[25:23];
          held_q.ea <= issue_ea;
          held_q.gpr_index <= issue_i.insn[20:16];
          held_q.gpr_value <= issue_ea;
          held_q.gpr_update <= decoded.kind == DK_MEMORY && decoded.mem_update;
          mem_q <= '0;
          mem_q.tag <= issue_i.tag;
          mem_q.ea <= issue_ea;
          mem_q.size_bytes <= decoded.mem_single || decoded.mem_integer ? 4'd4 : 4'd8;
          mem_q.write <= decoded.mem_store;
          arith_req_q <= '0;
          arith_req_q.tag <= issue_i.tag;
          arith_req_q.op <= decoded.op;
          arith_req_q.a <= issue_a;
          arith_req_q.b <= issue_b;
          arith_req_q.c <= issue_c;
          arith_req_q.rn <= fpscr_q[1:0];
          arith_req_q.ni <= fpscr_q[2];
          arith_req_q.ve <= fpscr_q[7];
          arith_req_q.oe <= fpscr_q[6];
          arith_req_q.ue <= fpscr_q[5];
          arith_req_q.ze <= fpscr_q[4];
          arith_req_q.single_result <= decoded.single_result;
          if (decoded.kind == DK_ILLEGAL) begin
            held_q.exception <= FPU_ILLEGAL;
            held_q.gpr_update <= 1'b0;
            state_q <= READY;
          end else if (!issue_i.msr_fp && fp_opcode_class) begin
            held_q.exception <= FPU_UNAVAILABLE;
            held_q.gpr_update <= 1'b0;
            state_q <= READY;
          end else begin
            case (decoded.kind)
              DK_ARITH: state_q <= SEND_ARITH;
              DK_MOVE: begin
                held_q.fpr_write <= 1'b1;
                case (decoded.move_kind)
                  2'd1: held_q.fpr_value <= {~issue_b[63],issue_b[62:0]};
                  2'd2: held_q.fpr_value <= {1'b1,issue_b[62:0]};
                  2'd3: held_q.fpr_value <= {1'b0,issue_b[62:0]};
                  default: held_q.fpr_value <= issue_b;
                endcase
                held_q.cr_write <= issue_i.insn[0];
                held_q.cr_field <= 3'd1;
                held_q.cr_value <= fpscr_q[31:28];
                state_q <= READY;
              end
              DK_FSEL: begin
                held_q.fpr_write <= 1'b1;
                held_q.fpr_value <= ((issue_a[62:52] == 11'h7ff && issue_a[51:0] != 52'd0) ||
                                     (issue_a[63] && issue_a[62:0] != 63'd0)) ? issue_b : issue_c;
                held_q.cr_write <= issue_i.insn[0];
                held_q.cr_field <= 3'd1;
                held_q.cr_value <= fpscr_q[31:28];
                state_q <= READY;
              end
              DK_MFFS: begin
                held_q.fpr_write <= 1'b1;
                held_q.fpr_value <= {32'd0,fpscr_q};
                held_q.cr_write <= issue_i.insn[0];
                held_q.cr_field <= 3'd1;
                held_q.cr_value <= fpscr_q[31:28];
                state_q <= READY;
              end
              DK_MCRFS: begin
                held_q.fpscr_write <= 1'b1;
                held_q.fpscr_value <= proposed_fpscr;
                held_q.cr_write <= 1'b1;
                held_q.cr_field <= issue_i.insn[25:23];
                held_q.cr_value <= fpscr_q[31-4*int'(issue_i.insn[20:18]) -: 4];
                state_q <= READY;
              end
              DK_MTFS: begin
                held_q.fpscr_write <= 1'b1;
                held_q.fpscr_value <= proposed_fpscr;
                if ((issue_i.msr_fe0 || issue_i.msr_fe1) && proposed_fpscr[30])
                  held_q.exception <= FPU_FP_ENABLED;
                held_q.cr_write <= issue_i.insn[0];
                held_q.cr_field <= 3'd1;
                held_q.cr_value <= proposed_fpscr[31:28];
                state_q <= READY;
              end
              DK_MEMORY: begin
                if (issue_ea[1:0] != 2'b00) begin
                  held_q.exception <= FPU_ALIGNMENT;
                  held_q.gpr_update <= 1'b0;
                  state_q <= READY;
                end else begin
                  if (decoded.mem_store) begin
                    held_q.store <= 1'b1;
                    if (decoded.mem_integer) mem_q.data <= {32'd0,fpr_q[issue_i.insn[25:21]][31:0]};
                    else if (decoded.mem_single)
                      mem_q.data <= {32'd0,narrow_single(fpr_q[issue_i.insn[25:21]])};
                    else mem_q.data <= fpr_q[issue_i.insn[25:21]];
                  end
                  state_q <= SEND_MEM;
                end
              end
              default: state_q <= READY;
            endcase
          end
        end
        SEND_ARITH: if (arith_req_ready) state_q <= WAIT_ARITH;
        WAIT_ARITH: if (arith_rsp_valid && pending_match_arith) begin
            held_q.fpr_write <= arith_rsp.write_result;
            held_q.fpr_value <= arith_rsp.result;
            held_q.fpscr_write <= 1'b1;
            held_q.fpscr_value <= arith_fpscr_next;
            held_q.cr_write <= arith_rsp.compare_valid ||
                               (arith_req_q.op != FP_CMPU && arith_req_q.op != FP_CMPO &&
                                issue_rc_q);
            held_q.cr_field <= arith_rsp.compare_valid ? held_q.cr_field : 3'd1;
            held_q.cr_value <= arith_rsp.compare_valid ? arith_rsp.fpcc :
                               arith_fpscr_next[31:28];
            if (issue_fe_any_q && arith_fpscr_next[30])
              held_q.exception <= FPU_FP_ENABLED;
            state_q <= READY;
        end
        SEND_MEM: if (mem_req_ready_i) state_q <= WAIT_MEM;
        WAIT_MEM: if (mem_rsp_valid_i && pending_match_mem) begin
          if (mem_rsp_i.fault) begin
            held_q.exception <= FPU_MEMORY_FAULT;
            held_q.fault_code <= mem_rsp_i.fault_code;
            held_q.fault_info <= mem_rsp_i.fault_info;
            held_q.store <= 1'b0;
            held_q.gpr_update <= 1'b0;
          end else if (!mem_q.write) begin
            held_q.fpr_write <= 1'b1;
            held_q.fpr_value <= (mem_q.size_bytes == 4'd4) ?
                                widen_single(mem_rsp_i.data[31:0]) : mem_rsp_i.data;
          end
          state_q <= READY;
        end
        READY: if (commit_ready_o) begin
            if (held_q.exception == FPU_NO_EXCEPTION || held_q.exception == FPU_FP_ENABLED) begin
              if (held_q.fpr_write) fpr_q[held_q.fpr_index] <= held_q.fpr_value;
              if (held_q.fpscr_write) fpscr_q <= held_q.fpscr_value;
            end
            state_q <= IDLE;
        end
        default: state_q <= IDLE;
      endcase
    end
  end
endmodule
`default_nettype wire
