// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Core clock: 50 MHz from the 50 MHz board clock. The framework constraints
// find the output clock at *|pll|pll_inst|altera_pll_i|*.
`timescale 1ns/10ps
module pll (
	input  wire refclk,
	input  wire rst,
	output wire outclk_0,
	output wire locked
);
	pll_core pll_inst (.refclk(refclk), .rst(rst), .outclk_0(outclk_0), .locked(locked));
endmodule

module pll_core (
	input  wire refclk,
	input  wire rst,
	output wire outclk_0,
	output wire locked
);
	altera_pll #(
		.fractional_vco_multiplier("false"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(1),
		.output_clock_frequency0("50.000000 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.pll_type("General"),
		.pll_subtype("General")
	) altera_pll_i (
		.rst(rst),
		.outclk({outclk_0}),
		.locked(locked),
		.fboutclk(),
		.fbclk(1'b0),
		.refclk(refclk)
	);
endmodule
