// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Lint and elaboration top for one CPU_VARIANT, selected by its integer
// encoding so the command line can set it.
module tb_variant_lint #(
  parameter int VARIANT = 0
);
  // Elaboration only: the pins stay open.
  /* verilator lint_off PINMISSING */
  ppc603e #(.CPU_VARIANT(ppc_pkg::cpu_variant_e'(VARIANT))) chip ();
  /* verilator lint_on PINMISSING */
endmodule
