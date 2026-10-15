# CLAUDED
# Run one simulation suite from a generated project.
#   vivado -mode batch -source vivado/run_suite.tcl -tclargs <target> <suite> [top_module]
# e.g. vivado -mode batch -source vivado/run_suite.tcl -tclargs nexys_a7 synaptic_module tb_SM_g_accumulator
set script_dir [file dirname [file normalize [info script]]]
if {$argc < 2} { error "usage: -tclargs <target> <suite> [top_module]" }
set target_name [lindex $argv 0]
set suite       [lindex $argv 1]

set target_file [file join $script_dir config targets $target_name.tcl]
if {![file exists $target_file]} { error "Unknown target '$target_name' (no $target_file)" }
array set target {}
source $target_file
if {[info exists target(proj_name)]} { set proj_name $target(proj_name) } else { set proj_name caravel_$target_name }

open_project [file join $script_dir project $proj_name $proj_name.xpr]
set fs [get_filesets sim_$suite]
if {$argc > 2} { set_property top [lindex $argv 2] $fs }
update_compile_order -fileset $fs
launch_simulation -simset $fs -mode behavioral
close_project