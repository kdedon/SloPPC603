# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Ranks setup paths of a mapped (not fitted) project with the project SDC.
# Usage: quartus_sta -t post_map_paths.tcl <project> <revision> <out_prefix> [post_map]
# Writes <out_prefix>.summary.txt (the 400 worst setup paths of every clock)
# and <out_prefix>.full.txt (the 3 worst in full). Post-map delays have no
# routing, so the ranking matters, not the slack.
set project [lindex $quartus(args) 0]
set revision [lindex $quartus(args) 1]
set out [lindex $quartus(args) 2]
set mode [lindex $quartus(args) 3]
project_open $project -revision $revision
if {$mode eq "post_map"} {
  create_timing_netlist -post_map -model slow
} else {
  create_timing_netlist -model slow
}
read_sdc
update_timing_netlist
report_timing -setup -npaths 400 -detail summary -file "${out}.summary.txt"
report_timing -setup -npaths 3 -detail full_path -file "${out}.full.txt"
delete_timing_netlist
project_close
