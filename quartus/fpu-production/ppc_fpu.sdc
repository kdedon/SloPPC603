# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Same-clock virtual ports; not board timing.
create_clock -name fpu_clk -period 20.000 [get_ports {clk_i}]
derive_clock_uncertainty
set_input_delay -clock fpu_clk -max 0.000 [remove_from_collection [all_inputs] [get_ports {clk_i}]]
set_input_delay -clock fpu_clk -min 0.000 [remove_from_collection [all_inputs] [get_ports {clk_i}]]
set_output_delay -clock fpu_clk -max 0.000 [all_outputs]
set_output_delay -clock fpu_clk -min 0.000 [all_outputs]

# A fit variant wraps the shell in one boundary register per port (port P:
# P_ibq or P_obq) standing in for the integrator's flop. Only the hop between
# a virtual pin and its own boundary register is cut, one bit at a time;
# paths between the boundary registers and the FPU are timed.
# '?' stands for each bracket, as TimeQuest name filters treat them specially.
proc escaped {name} { return [string map {[ ? ] ?} $name] }
proc boundary_register {name suffix} {
  if {![regexp {^([A-Za-z0-9_]+)(.*)$} $name -> base rest]} { return {} }
  return [get_registers -nowarn [escaped "${base}_${suffix}${rest}"]]
}
set boundary_paired 0
set boundary_unpaired 0
foreach_in_collection id [remove_from_collection [all_inputs] [get_ports {clk_i}]] {
  set name [get_port_info -name $id]
  set port [get_ports [escaped $name]]
  set reg [boundary_register $name ibq]
  if {[get_collection_size $reg] == 1} {
    set_false_path -from $port -to $reg
    incr boundary_paired
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
    incr boundary_paired
  } elseif {[get_collection_size [get_fanins $port]] != 0} {
    incr boundary_unpaired
  }
}
if {$boundary_paired != 0 && $boundary_unpaired != 0} {
  post_message -type critical_warning "$boundary_unpaired driven ports lack a boundary register"
}
