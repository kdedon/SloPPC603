# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Write the worst failing setup paths of a completed fit, one line each.
# Usage: quartus_sta -t failing_paths.tcl <revision> <out_file>
# Per corner: slack, launch clock, from, to for the worst path into each of up
# to 200 failing endpoints; then the full path of the worst one at the first
# failing corner to <out_file>.detail.txt.
set revision [lindex $quartus(args) 0]
set out_file [lindex $quartus(args) 1]
project_open $revision -revision $revision
create_timing_netlist
read_sdc
update_timing_netlist
set out [open $out_file w]
set detail "${out_file}.detail.txt"
file delete -force $detail
set first 1
foreach cond [get_available_operating_conditions] {
  set_operating_conditions $cond
  update_timing_netlist
  set paths [get_timing_paths -setup -npaths 200 -nworst 1 -less_than_slack 0.0]
  foreach_in_collection path $paths {
    puts $out "$cond\t[get_path_info $path -slack]\t[get_clock_info -name [get_path_info $path -from_clock]]\t[get_node_info -name [get_path_info $path -from]]\t[get_node_info -name [get_path_info $path -to]]"
  }
  if {$first && [get_collection_size $paths] > 0} {
    report_timing -setup -npaths 3 -detail full_path -less_than_slack 0.0 -file $detail
    set first 0
  }
}
close $out
project_close
