# Provisional 50 MHz, same-clock measurement with registered virtual I/O.
# This is not a board or PID7v clock/interface constraint set.
create_clock -name core_clk -period 20.000 [get_ports {clk_i}]
derive_clock_uncertainty
set_input_delay -clock core_clk -max 0.000 [remove_from_collection [all_inputs] [get_ports {clk_i}]]
set_input_delay -clock core_clk -min 0.000 [remove_from_collection [all_inputs] [get_ports {clk_i}]]
set_output_delay -clock core_clk -max 0.000 [all_outputs]
set_output_delay -clock core_clk -min 0.000 [all_outputs]
# rst_ni is asynchronous to core_clk; its only load is the first flop of the
# measurement top's two-flop reset synchronizer.
set_false_path -from [get_ports {rst_ni}] -to [get_registers {rst_sync_q[0]}]
# Every other data input loads only its boundary register (*_ibq) and every
# output is driven only by one (*_obq); those registers model the upstream and
# downstream flops. The pin-to-register hop of a virtual pin has no physical
# delay or clock insertion to compare against, so it is not timed; every path
# into or out of the core is timed register to register.
set_false_path -from [remove_from_collection [all_inputs] [get_ports {clk_i rst_ni}]] -to [get_registers {*_ibq*}]
set_false_path -from [get_registers {*_obq*}] -to [all_outputs]
