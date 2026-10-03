# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Implements docs/INTERFACE_TIMING_CONTRACT.md for the integrated measurement top.
# Board pin timing is not modelled: every port is a virtual pin.

# C1: one core clock. The period is the MVP gate; 66 MHz is checked by
# re-timing this fit with report-target-paths.sh.
create_clock -name core_clk -period 20.000 [get_ports {clk_i}]
derive_clock_uncertainty

# Virtual pins carry no board delay; zero budgets make every port an ideal
# core_clk register.
set data_in [remove_from_collection [all_inputs] [get_ports {clk_i rst_ni}]]
set_input_delay -clock core_clk -max 0.000 $data_in
set_input_delay -clock core_clk -min 0.000 $data_in
set_input_delay -clock core_clk -max 0.000 [get_ports {rst_ni}]
set_input_delay -clock core_clk -min 0.000 [get_ports {rst_ni}]
set_output_delay -clock core_clk -max 0.000 [all_outputs]
set_output_delay -clock core_clk -min 0.000 [all_outputs]

# C5: ABB/DBB negation launches on the falling edge; its path into *_obq is
# timed at half the period by default and needs no constraint here.

# C2: rst_ni is asynchronous at the pin. Only the first synchronizer flop
# samples it; everything after rst_sync_q[0] is timed.
set rst_first [get_registers {rst_sync_q[0]}]
if {[get_collection_size $rst_first] != 1} {
  post_message -type critical_warning "reset synchronizer flop not found"
}
set_false_path -from [get_ports {rst_ni}] -to $rst_first

# C3/C4: each data port is paired with one boundary register that stands in
# for the integrator's flop (port P: register P_ibq for inputs, P_obq for
# outputs). Only the hop between a virtual pin and its own boundary register
# is cut, one bit at a time; any other load of a port stays timed. Paths from
# *_ibq into the core and from the core into *_obq are timed register to
# register at the full period.
# '?' stands for each bracket, as TimeQuest name filters treat them specially.
proc escaped {name} { return [string map {[ ? ] ?} $name] }
proc boundary_register {name suffix} {
  if {![regexp {^([A-Za-z0-9_]+)(.*)$} $name -> base rest]} { return {} }
  return [get_registers -nowarn [escaped "${base}_${suffix}${rest}"]]
}
# A port without its register is either constant (no path) or reaches other
# logic; the second case stays timed and is flagged.
set boundary_unpaired 0
foreach_in_collection id $data_in {
  set name [get_port_info -name $id]
  set port [get_ports [escaped $name]]
  set reg [boundary_register $name ibq]
  if {[get_collection_size $reg] == 1} {
    set_false_path -from $port -to $reg
  } elseif {[get_collection_size [get_fanouts $port]] != 0} {
    incr boundary_unpaired
  }
}
foreach_in_collection id [all_outputs] {
  set name [get_port_info -name $id]
  set port [get_ports [escaped $name]]
  set reg [boundary_register $name obq]
  if {[get_collection_size $reg] == 1} {
    set_false_path -from $reg -to $port
  } elseif {[get_collection_size [get_fanins $port]] != 0} {
    incr boundary_unpaired
  }
}
if {$boundary_unpaired != 0} {
  post_message -type critical_warning "$boundary_unpaired driven ports lack a boundary register"
}
