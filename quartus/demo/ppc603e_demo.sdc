# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Demonstration system, one clock at the 50 MHz MVP gate. Every port is a
# virtual pin with no board delay.
create_clock -name clk -period 20.000 [get_ports {clk_i}]
derive_clock_uncertainty
set ports_in [remove_from_collection [all_inputs] [get_ports {clk_i}]]
set_input_delay -clock clk -max 0.000 $ports_in
set_input_delay -clock clk -min 0.000 $ports_in
set_output_delay -clock clk -max 0.000 [all_outputs]
set_output_delay -clock clk -min 0.000 [all_outputs]
