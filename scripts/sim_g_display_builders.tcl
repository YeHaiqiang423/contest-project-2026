set project_root [file normalize [file join [file dirname [info script]] ..]]
set selected_top [expr {[llength $argv] > 0 ? [lindex $argv 0] : "tb_g_time_domain_display"}]
set build_dir [file join $project_root results ${selected_top}_sim]
create_project -force ${selected_top}_sim $build_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files [list \
    [file join $project_root rtl src g_unsigned_divider.v] \
    [file join $project_root rtl src g_integer_sqrt.v] \
    [file join $project_root rtl src g_time_domain_display.v] \
    [file join $project_root rtl src g_spectrum_display.v]]
add_files -fileset sim_1 [file join $project_root rtl tb ${selected_top}.sv]
set_property top $selected_top [get_filesets sim_1]
set_property -name {xsim.elaborate.debug_level} -value {typical} \
    -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project

