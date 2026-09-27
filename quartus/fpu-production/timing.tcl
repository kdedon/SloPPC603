project_open ppc_fpu
create_timing_netlist -post_map
read_sdc ppc_fpu.sdc
update_timing_netlist
report_clocks -file output_files/clocks.txt
check_timing -file output_files/check_timing.txt
report_clock_fmax_summary -file output_files/fmax.txt
report_timing -setup -npaths 10 -detail full_path -file output_files/setup.txt
report_timing -hold -npaths 10 -detail full_path -file output_files/hold.txt
report_ucp -file output_files/unconstrained.txt
foreach {label pattern} {multiply *multiply_q* aligned *aligned_q* add *add_q* divider *div* response *response*} {
    set nodes [get_registers $pattern]
    if {[get_collection_size $nodes] > 0} {
        report_timing -setup -to $nodes -npaths 1 -detail full_path -file output_files/stage_$label.txt
    }
}
delete_timing_netlist
project_close
