create_clock -name core_clk -period 20.000 [get_ports {clk_i}]
set_input_delay -clock core_clk 0.000 [get_ports {rst_ni stimulus_i[*]}]
set_output_delay -clock core_clk 0.000 [get_ports {activity_o}]
