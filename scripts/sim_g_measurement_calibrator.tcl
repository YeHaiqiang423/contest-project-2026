set project_root [file normalize [file join [file dirname [info script]] ..]]
set gui_mode [expr {[llength $argv] > 0 && [lindex $argv 0] eq "gui"}]
set build_dir [file join $project_root results g_measurement_calibrator_sim]
create_project -force g_measurement_calibrator_sim $build_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files [list \
    [file join $project_root rtl src g_integer_sqrt.v] \
    [file join $project_root rtl src g_unsigned_divider.v] \
    [file join $project_root rtl src g_measurement_calibrator.v]]
add_files -fileset sim_1 \
    [file join $project_root rtl tb tb_g_measurement_calibrator.sv]
set_property top tb_g_measurement_calibrator [get_filesets sim_1]
set_property -name {xsim.elaborate.debug_level} -value {typical} \
    -objects [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
if {$gui_mode} {
    source [file join $project_root scripts wave_g_measurement_calibrator.tcl]
    puts "MEASUREMENT_CALIBRATOR_GUI_READY: use Run All"
    return
}
run all
close_sim
close_project
