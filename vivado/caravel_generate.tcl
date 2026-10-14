# CLAUDED
# Generate the local Vivado project from vivado/config/.
#
#   vivado -mode batch -source vivado/caravel_generate.tcl -tclargs nexys_a7
#   vivado -mode batch -source vivado/caravel_generate.tcl -tclargs kria_k26
#
# Output goes to vivado/project/ (gitignored). It is deleted and rebuilt on
# every run, so never keep hand edits there -- change the config instead.

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file dirname $script_dir]
set cfg_dir    [file join $script_dir config]
set proj_name  caravel_kria
set proj_dir   [file join $script_dir project]

set target_name kria_kr26
if {$argc > 0} { set target_name [lindex $argv 0] }
set target_file [file join $cfg_dir targets $target_name.tcl]
if {![file exists $target_file]} {
    error "Unknown target '$target_name' (no $target_file)"
}
array set target {}
source $target_file
source [file join $cfg_dir sources.tcl]

# Expand globs (relative to $root), minus anything matching an exclude glob.
proc glob_files {root patterns {excludes {}}} {
    set out {}
    foreach pat $patterns {
        set hits [lsort [glob -nocomplain -directory $root $pat]]
        if {[llength $hits] == 0} { puts "WARNING: no files match '$pat'" }
        foreach f $hits {
            if {[file isdirectory $f]} continue
            set skip 0
            foreach x $excludes {
                if {[string match [file join $root $x] $f]} { set skip 1; break }
            }
            if {!$skip} { lappend out $f }
        }
    }
    return [lsort -unique $out]
}

# --- project ---------------------------------------------------------------
create_project -force $proj_name $proj_dir -part $target(part)
if {[llength [get_board_parts -quiet $target(board_part)]]} {
    set_property board_part $target(board_part) [current_project]
} else {
    puts "WARNING: board part $target(board_part) not installed; using part only"
}
set_property target_language Verilog [current_project]

# --- design sources --------------------------------------------------------
set rtl_files {}
dict for {group patterns} $rtl_groups {
    lappend rtl_files {*}[glob_files $repo_root $patterns $rtl_exclude]
}
add_files -norecurse -fileset sources_1 $rtl_files
set inc {}
foreach d $include_dirs { lappend inc [file join $repo_root $d] }
set_property include_dirs $inc [get_filesets sources_1]
set_property top $target(top) [get_filesets sources_1]

# --- constraints -----------------------------------------------------------
foreach c $target(constraints) {
    set path [file join $repo_root $c]
    if {[file exists $path]} {
        add_files -norecurse -fileset constrs_1 $path
    } else {
        puts "WARNING: constraints file missing: $c"
    }
}

# --- IP (copied into the project so the repo's .xci files stay untouched) --
foreach x $target(ip) {
    import_ip -quiet [file join $repo_root $x]
}
if {[llength [get_ips -quiet]]} {
    catch {upgrade_ip -quiet [get_ips]}
    catch {generate_target all [get_ips]}
}

# --- simulation suites: one simset each ------------------------------------
catch {delete_fileset [get_filesets sim_1]}
dict for {name suite} $sim_suites {
    set fs sim_$name
    create_fileset -simset $fs
    set tbs [glob_files $repo_root [dict get $suite files]]
    if {[llength $tbs]} { add_files -norecurse -fileset $fs $tbs }
    set extra [glob_files $repo_root [dict get $suite extra]]
    if {[llength $extra]} { add_files -norecurse -fileset $fs $extra }
    set_property top [dict get $suite top] [get_filesets $fs]
    set_property include_dirs $inc [get_filesets $fs]
    if {[llength [dict get $suite defines]]} {
        set_property verilog_define [dict get $suite defines] [get_filesets $fs]
    }
    set_property -name xsim.simulate.runtime -value [dict get $suite runtime] \
        -objects [get_filesets $fs]
}
current_fileset -simset [get_filesets sim_$default_suite]

update_compile_order -fileset sources_1
puts "Generated $proj_dir/$proj_name.xpr for target '$target_name'"