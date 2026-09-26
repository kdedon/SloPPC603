create_clock -name core_clk -period 20.000 [get_ports {clk_i}]
derive_clock_uncertainty
set_input_delay -clock core_clk -max 0.000 [get_ports {rst_ni stimulus_i[*]}]
set_input_delay -clock core_clk -min 0.000 [get_ports {rst_ni stimulus_i[*]}]
set_output_delay -clock core_clk -max 0.000 [get_ports {activity_o}]
set_output_delay -clock core_clk -min 0.000 [get_ports {activity_o}]
