// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Lint and elaboration top for the FPU-enabled chip, selecting FPU_IMPL by
// its integer encoding so the command line can set it.
module tb_fpu_impl_lint #(
  parameter int FPU_IMPL = 0
);
  // Elaboration only: the pins stay open.
  /* verilator lint_off PINMISSING */
  ppc603e #(.ENABLE_FPU(1'b1),
    .FPU_IMPL(ppc_fpu_pkg::fpu_impl_e'(FPU_IMPL))) chip ();
  /* verilator lint_on PINMISSING */
endmodule
`default_nettype wire
