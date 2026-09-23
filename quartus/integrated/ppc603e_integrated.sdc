# Provisional 50 MHz, same-clock virtual I/O measurement only.
# This is not a board or PID7v clock/60x interface constraint set.
create_clock -name core_clk -period 20.000 [get_ports {clk_i}]
set_input_delay -clock core_clk -max 0.000 [remove_from_collection [all_inputs] [get_ports {clk_i}]]
set_input_delay -clock core_clk -min 0.000 [remove_from_collection [all_inputs] [get_ports {clk_i}]]
set_output_delay -clock core_clk -max 0.000 [all_outputs]
set_output_delay -clock core_clk -min 0.000 [all_outputs]
