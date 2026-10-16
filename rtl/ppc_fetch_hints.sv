// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Stateless physical-word hints, before cache storage or scalar-source selection.
// Each word is {raw CR writer, branch class, needs IU}; faults are handled later.
module ppc_fetch_hints #(
  parameter bit ENABLE_SUPERVISOR_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_LIVE_CONTEXT = 1'b0,
  parameter bit ENABLE_TIMERS = 1'b0,
  parameter bit ENABLE_RUNTIME_BAT = 1'b0,
  parameter bit ENABLE_SEGMENT_REGISTERS = 1'b0,
  parameter bit ENABLE_TLB_INVALIDATE = 1'b0,
  parameter bit ENABLE_TLB_LOAD = 1'b0,
  parameter bit ENABLE_SDR1 = 1'b0,
  parameter bit ENABLE_TLB_MISS_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_CACHE_INSTRUCTIONS = 1'b0,
  // Cache-block instructions, lwarx/stwcx. and sync go to a data cache.
  parameter bit ENABLE_DATA_CACHE = 1'b0,
  parameter bit ENABLE_BYTE_REVERSE = 1'b0,
  parameter bit ENABLE_MULTIPLE_STRING = 1'b0,
  parameter bit ENABLE_RESERVATION = 1'b0,
  parameter bit ENABLE_DEBUG_EXCEPTIONS = 1'b0,
  // Illegal and invalid forms, traps, FP class, PVR/HID0/HID1/EAR and
  // eciwx/ecowx.
  parameter bit ENABLE_FULL_DECODE = 1'b0,
  // FP uops carry their CR field, update and alignment metadata.
  parameter bit ENABLE_FPU = 1'b0,
  // Part the build models; HID1 and EAR exist only where cpu_cfg() says so,
  // and the 602 forms and SPRs only on the 602.
  parameter ppc_pkg::cpu_variant_e CPU_VARIANT = ppc_pkg::CPU_PID7V_603E
) (
  input logic [255:0] line_i,
  input logic [31:0] scalar_i,
  output logic [23:0] line_hints_o,
  output logic [2:0] scalar_hints_o
);
  import ppc_pkg::*;
  genvar w;
  generate
  for (w = 0; w < 9; w = w + 1) begin : g_word
    logic [31:0] word;
    // Only classification/CR permission fields are consumed from the decoder.
    /* verilator lint_off UNUSEDSIGNAL */
    uop_t decoded;
    /* verilator lint_on UNUSEDSIGNAL */
    fetch_lookahead_t word_class;
    logic [2:0] hints;
    if (w < 8) begin : g_line
      assign word = line_i[255-32*w -:32];
      assign line_hints_o[23-3*w -:3] = hints;
    end else begin : g_scalar
      assign word = scalar_i;
      assign scalar_hints_o = hints;
    end
    ppc_decode #(
      .ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS),
      .ENABLE_LIVE_CONTEXT(ENABLE_LIVE_CONTEXT),
      .ENABLE_TIMERS(ENABLE_TIMERS),
      .ENABLE_RUNTIME_BAT(ENABLE_RUNTIME_BAT),
      .ENABLE_SEGMENT_REGISTERS(ENABLE_SEGMENT_REGISTERS),
      .ENABLE_TLB_INVALIDATE(ENABLE_TLB_INVALIDATE),
      .ENABLE_TLB_LOAD(ENABLE_TLB_LOAD),
      .ENABLE_SDR1(ENABLE_SDR1),
      .ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS),
      .ENABLE_CACHE_INSTRUCTIONS(ENABLE_CACHE_INSTRUCTIONS),
      .ENABLE_DATA_CACHE(ENABLE_DATA_CACHE),
      .ENABLE_BYTE_REVERSE(ENABLE_BYTE_REVERSE),
      .ENABLE_MULTIPLE_STRING(ENABLE_MULTIPLE_STRING),
      .ENABLE_RESERVATION(ENABLE_RESERVATION),
      .ENABLE_DEBUG_EXCEPTIONS(ENABLE_DEBUG_EXCEPTIONS),
      .ENABLE_FULL_DECODE(ENABLE_FULL_DECODE),
      .ENABLE_FPU(ENABLE_FPU),
      .CPU_VARIANT(CPU_VARIANT)
    ) decode (.insn_i(word), .uop_o(decoded));
    assign word_class = fetch_lookahead(decoded, word, 1'b0);
    assign hints = {cr_writer(decoded), word_class};
  end
  endgenerate
endmodule
`default_nettype wire
