// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Decode-space sweep of the translated MVP profile with ENABLE_FULL_DECODE:
// every primary opcode with varied payloads, every opcode-19/31/59/63
// extended opcode with varied register/reserved fields, and the whole SPR
// space. No word may decode to a diagnostic (illegal). Words the profile
// without ENABLE_FULL_DECODE accepts must decode identically; FP, trap,
// eciwx/ecowx and the new SPRs must be rejected there (negative control).
module tb_decode_sweep;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t full, base;

  ppc_decode #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1), .ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_TIMERS(1'b1), .ENABLE_RUNTIME_BAT(1'b1),
    .ENABLE_SEGMENT_REGISTERS(1'b1), .ENABLE_TLB_INVALIDATE(1'b1),
    .ENABLE_TLB_LOAD(1'b1), .ENABLE_SDR1(1'b1),
    .ENABLE_TLB_MISS_EXCEPTIONS(1'b1), .ENABLE_CACHE_INSTRUCTIONS(1'b1),
    .ENABLE_BYTE_REVERSE(1'b1), .ENABLE_MULTIPLE_STRING(1'b1),
    .ENABLE_RESERVATION(1'b1), .ENABLE_DEBUG_EXCEPTIONS(1'b1),
    .ENABLE_FULL_DECODE(1'b1)
  ) full_decode (.insn_i(insn), .uop_o(full));
  ppc_decode #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1), .ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_TIMERS(1'b1), .ENABLE_RUNTIME_BAT(1'b1),
    .ENABLE_SEGMENT_REGISTERS(1'b1), .ENABLE_TLB_INVALIDATE(1'b1),
    .ENABLE_TLB_LOAD(1'b1), .ENABLE_SDR1(1'b1),
    .ENABLE_TLB_MISS_EXCEPTIONS(1'b1), .ENABLE_CACHE_INSTRUCTIONS(1'b1),
    .ENABLE_BYTE_REVERSE(1'b1), .ENABLE_MULTIPLE_STRING(1'b1),
    .ENABLE_RESERVATION(1'b1), .ENABLE_DEBUG_EXCEPTIONS(1'b1),
    .ENABLE_FULL_DECODE(1'b0)
  ) base_decode (.insn_i(insn), .uop_o(base));

  typedef enum int {C_OTHER, C_ILLEGAL, C_FPU, C_TRAP, C_NEW} cls_t;
  int probes = 0, n_same = 0, n_illegal = 0, n_fpu = 0, n_trap = 0, n_new = 0;
  int n_priv = 0;

  // Reference classification from UM Table A-1 and UM 2.3.1.3.
  function automatic cls_t classify(input logic [31:0] w);
    logic [5:0] op;
    logic [9:0] xo;
    logic [4:0] axo;
    logic [9:0] spr;
    op = w[31:26];
    xo = w[10:1];
    axo = w[5:1];
    spr = {w[15:11], w[20:16]};
    case (op)
      6'd1, 6'd2, 6'd4, 6'd5, 6'd6, 6'd9, 6'd22, 6'd30,
      6'd56, 6'd57, 6'd58, 6'd60, 6'd61, 6'd62: return C_ILLEGAL;
      6'd3: return C_TRAP;
      6'd48, 6'd49, 6'd50, 6'd51, 6'd52, 6'd53, 6'd54, 6'd55: return C_FPU;
      6'd59: return (axo inside {5'd18, 5'd20, 5'd21, 5'd24, 5'd25, 5'd28,
                                 5'd29, 5'd30, 5'd31}) ? C_FPU : C_ILLEGAL;
      6'd63: return ((axo inside {5'd18, 5'd20, 5'd21, 5'd23, 5'd25, 5'd26,
                                  5'd28, 5'd29, 5'd30, 5'd31}) ||
                     (xo inside {10'd0, 10'd12, 10'd14, 10'd15, 10'd32, 10'd38,
                                 10'd40, 10'd64, 10'd70, 10'd72, 10'd134,
                                 10'd136, 10'd264, 10'd583, 10'd711})) ?
                    C_FPU : C_ILLEGAL;
      6'd31: begin
        if (xo inside {10'd535, 10'd567, 10'd599, 10'd631, 10'd663, 10'd695,
                       10'd727, 10'd759, 10'd983}) return C_FPU;
        if (xo == 10'd4) return w[0] ? C_ILLEGAL : C_TRAP;
        if ((xo == 10'd310 || xo == 10'd438) && !w[0]) return C_NEW;
        if ((xo inside {10'd339, 10'd371, 10'd467}) && !w[0] &&
            ((spr == SPR_HID0) || (spr == SPR_HID1) || (spr == SPR_EAR) ||
             ((xo != 10'd467) && (spr == SPR_PVR)))) return C_NEW;
        if ((xo == 10'd598) && ((w & ~32'h0060_0000) == 32'h7c00_04ac) &&
            (w != 32'h7c00_04ac)) return C_NEW;
        return C_OTHER;
      end
      default: return C_OTHER;
    endcase
  endfunction

  task automatic fail(input string why);
    $fatal(1, "%s insn=%08x full.special=%0d base.illegal=%0d base.special=%0d",
           why, insn, full.special_op, base.illegal, base.special_op);
  endtask

  task automatic probe(input logic [31:0] w);
    cls_t c;
    bit base_ok;
    insn = w;
    #1;
    probes++;
    c = classify(w);
    base_ok = !base.illegal && (base.special_op != SPECIAL_PROGRAM_ILLEGAL);
    if (full.illegal) fail("diagnostic decode");
    case (c)
      C_ILLEGAL: begin
        if (full.special_op != SPECIAL_PROGRAM_ILLEGAL) fail("illegal opcode not program");
        n_illegal++;
      end
      C_FPU: begin
        if (full.special_op != SPECIAL_FPU) fail("FP class");
        if (base_ok) fail("FP accepted without full decode");
        n_fpu++;
      end
      C_TRAP: begin
        if (full.special_op != SPECIAL_TRAP || full.branch_bo != w[25:21]) fail("trap");
        if (base_ok) fail("trap accepted without full decode");
        n_trap++;
      end
      C_NEW: begin
        if (full.special_op inside {SPECIAL_PROGRAM_ILLEGAL, SPECIAL_NONE})
          fail("new form rejected");
        if (base_ok) fail("new form accepted without full decode");
        n_new++;
      end
      default: begin
        if (base_ok) begin
          if (full != base) fail("accepted word decodes differently");
          n_same++;
        end else begin
          if (full.special_op != SPECIAL_PROGRAM_ILLEGAL) fail("invalid form not program");
          n_illegal++;
        end
      end
    endcase
    if (full.special_op == SPECIAL_PROGRAM_ILLEGAL && full.privileged) n_priv++;
  endtask

  localparam logic [31:0] payloads [6] = '{32'h0000_0000, 32'h03ff_ffff, 32'h02aa_5555,
                                          32'h0155_aaaa, 32'h0210_f81f, 32'h0000_0001};
  localparam logic [31:0] fields [10] = '{32'h0000_0000, 32'h03ff_f800, 32'h02aa_a800,
                                         32'h0155_5000, 32'h0210_f800, 32'h0000_f800,
                                         32'h000f_0000, 32'h03e0_0000, 32'h0060_0000,
                                         32'h0000_07c0};

  initial begin
    for (int op = 0; op < 64; op++)
      foreach (payloads[p]) probe((32'(op) << 26) | payloads[p]);
    for (int k = 0; k < 4; k++) begin
      logic [5:0] op;
      op = (k == 0) ? 6'd19 : (k == 1) ? 6'd31 : (k == 2) ? 6'd59 : 6'd63;
      for (int xo = 0; xo < 1024; xo++)
        for (int rc = 0; rc < 2; rc++)
          foreach (fields[f])
            probe({op, 26'b0} | fields[f] | (32'(xo) << 1) | 32'(rc));
    end
    // Whole SPR space for mfspr/mftb/mtspr, and undefined-SPR privilege.
    for (int spr = 0; spr < 1024; spr++)
      for (int x = 0; x < 3; x++) begin
        logic [9:0] xo;
        xo = (x == 0) ? 10'd339 : (x == 1) ? 10'd371 : 10'd467;
        probe((32'd31 << 26) | (32'd7 << 21) | ((32'(spr) & 31) << 16) |
              ((32'(spr) >> 5) << 11) | (32'(xo) << 1));
        if (full.special_op == SPECIAL_PROGRAM_ILLEGAL &&
            full.privileged != spr[4]) fail("undefined SPR privilege");
      end
    $display("PASS tb_decode_sweep: probes=%0d unchanged=%0d illegal=%0d fp=%0d trap=%0d new=%0d privileged_undefined=%0d",
             probes, n_same, n_illegal, n_fpu, n_trap, n_new, n_priv);
    $finish;
  end
endmodule
