# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Read-only detailed paths from a completed fit using its exact run SDC.
# Usage: quartus_sta -t all_corner_paths.tcl <project> <revision> <run_sdc> <out_dir>
if {[llength $quartus(args)] != 4} {
    error "expected project, revision, run SDC and output directory"
}
lassign $quartus(args) project revision run_sdc out
if {![file isfile $run_sdc]} {
    error "run SDC does not exist: $run_sdc"
}
file mkdir $out
project_open $project -revision $revision
create_timing_netlist
read_sdc $run_sdc
update_timing_netlist
foreach cond [get_available_operating_conditions] {
    set_operating_conditions $cond
    update_timing_netlist
    report_timing -setup -npaths 20 -nworst 1 -detail full_path -file "$out/setup_$cond.txt"
    report_timing -hold -npaths 3 -nworst 1 -detail full_path -file "$out/hold_$cond.txt"
}
delete_timing_netlist
project_close
