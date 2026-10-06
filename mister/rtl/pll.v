// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Core clock: SYS_MHZ (10 to 99) from the 50 MHz board clock. The framework
// constraints find the output clock at *|pll|pll_inst|altera_pll_i|*.
`timescale 1ns/10ps
module pll #(
	parameter SYS_MHZ = 50
) (
	input  wire refclk,
	input  wire rst,
	output wire outclk_0,
	output wire locked
);
	pll_core #(.SYS_MHZ(SYS_MHZ)) pll_inst (.refclk(refclk), .rst(rst), .outclk_0(outclk_0), .locked(locked));
endmodule

module pll_core #(
	parameter SYS_MHZ = 50
) (
	input  wire refclk,
	input  wire rst,
	output wire outclk_0,
	output wire locked
);
	localparam [8*13-1:0] FREQ = {8'd48 + SYS_MHZ / 10, 8'd48 + SYS_MHZ % 10, ".000000 MHz"};
	altera_pll #(
		.fractional_vco_multiplier("false"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(1),
		.output_clock_frequency0(FREQ),
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
