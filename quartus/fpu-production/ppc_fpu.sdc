# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Same-clock virtual ports; post-map measurement, not board timing.
create_clock -name fpu_clk -period 20.000 [get_ports {clk_i}]
derive_clock_uncertainty
set_input_delay -clock fpu_clk -max 0.000 [remove_from_collection [all_inputs] [get_ports {clk_i}]]
set_input_delay -clock fpu_clk -min 0.000 [remove_from_collection [all_inputs] [get_ports {clk_i}]]
set_output_delay -clock fpu_clk -max 0.000 [all_outputs]
set_output_delay -clock fpu_clk -min 0.000 [all_outputs]
