// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Lint and elaboration top for one CPU_VARIANT, selected by its integer
// encoding so the command line can set it. PLL is the PLL_CFG[0:3] strap
// code; a negative value takes the variant's default.
module tb_variant_lint #(
  parameter int VARIANT = 0,
  parameter int PLL = -1
);
  localparam ppc_pkg::cpu_variant_e CPU_VARIANT = ppc_pkg::cpu_variant_e'(VARIANT);
  localparam logic [3:0] PLL_CFG =
    (PLL < 0) ? ppc_pkg::pll_cfg_default(CPU_VARIANT) : 4'(PLL);
  // Elaboration only: the pins stay open.
  /* verilator lint_off PINMISSING */
  ppc603e #(.CPU_VARIANT(CPU_VARIANT), .PLL_CFG(PLL_CFG)) chip ();
  /* verilator lint_on PINMISSING */
endmodule
