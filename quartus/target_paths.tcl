# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Re-time a completed fit against another clock period; never fits.
# Usage: quartus_sta -t target_paths.tcl <revision> <period_ns> <out_file>
# Rewrites the project SDC's create_clock period, then writes the worst setup
# path per failing endpoint at every corner (corner, slack, from, to) to
# <out_file>, and the full path of the worst endpoint in each of the 40 worst
# destination-register groups at the first corner to <out_file>.paths.txt,
# and the worst boundary input, output and feedthrough path per corner to
# <out_file>.boundary.txt.
set revision [lindex $quartus(args) 0]
set period [lindex $quartus(args) 1]
set out_file [lindex $quartus(args) 2]
project_open $revision -revision $revision

set sdc_in [open "${revision}.sdc" r]
set sdc_text [read $sdc_in]
close $sdc_in
if {![regsub -- {-period [0-9.]+} $sdc_text "-period $period" sdc_text]} {
  post_message -type error "no create_clock -period in ${revision}.sdc"
  exit 1
}
set sdc_tmp "output_files/${revision}.target.sdc"
set sdc_out [open $sdc_tmp w]
puts -nonewline $sdc_out $sdc_text
close $sdc_out

proc escaped {name} { return [string map [list {[} ? {]} ?] $name] }

create_timing_netlist
read_sdc $sdc_tmp
update_timing_netlist

set out [open $out_file w]
set first 1
set detail_file "${out_file}.paths.txt"
file delete -force $detail_file
foreach cond [get_available_operating_conditions] {
  set_operating_conditions $cond
  update_timing_netlist
  set groups {}
  foreach_in_collection path [get_timing_paths -setup -npaths 20000 -nworst 1 -less_than_slack 0.0] {
    set from [get_node_info -name [get_path_info $path -from]]
    set to [get_node_info -name [get_path_info $path -to]]
    puts $out "$cond\t[get_path_info $path -slack]\t$from\t$to"
    if {$first} {
      regsub -all {\[[0-9]+\]|~.*$} $to {} group
      regsub {\.[^|]*$} $group {} group
      if {![dict exists $groups $group]} { dict set groups $group [list $from $to] }
    }
  }
  if {$first} {
    set n 0
    dict for {group ends} $groups {
      if {[incr n] > 40} break
      report_timing -setup -from [get_keepers [escaped [lindex $ends 0]]] -to [get_keepers [escaped [lindex $ends 1]]] \
        -npaths 1 -detail full_path -file $detail_file -append
    }
    set first 0
  }
}
close $out

# Boundary budget: worst setup path per class at every corner. The core-side
# delay of a class is period minus slack; docs/INTERFACE_TIMING_CONTRACT.md
# states the budget it must meet.
set ibq [get_keepers -nowarn {*_ibq*}]
set obq [get_keepers -nowarn {*_obq*}]
set boundary [open "${out_file}.boundary.txt" w]
foreach cond [get_available_operating_conditions] {
  set_operating_conditions $cond
  update_timing_netlist
  foreach {class paths} [list \
      input [get_timing_paths -setup -from $ibq -npaths 1] \
      output [get_timing_paths -setup -to $obq -npaths 1] \
      feedthrough [get_timing_paths -setup -from $ibq -to $obq -npaths 1]] {
    set line "$cond\t$class\tnone"
    foreach_in_collection path $paths {
      set line "$cond\t$class\t[get_path_info $path -slack]\t[get_node_info -name [get_path_info $path -from]]\t[get_node_info -name [get_path_info $path -to]]"
    }
    puts $boundary $line
    post_message "boundary: $line"
  }
}
close $boundary
delete_timing_netlist
project_close
