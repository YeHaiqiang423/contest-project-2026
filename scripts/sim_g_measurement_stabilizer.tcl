set project_root [file normalize [file join [file dirname [info script]] ..]]
set build_dir [file join $project_root results g_measurement_stabilizer_sim]
create_project -force g_measurement_stabilizer_sim $build_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files [file join $project_root rtl src g_measurement_stabilizer.v]
add_files -fileset sim_1 \
    [file join $project_root rtl tb tb_g_measurement_stabilizer.sv]
set_property top tb_g_measurement_stabilizer [get_filesets sim_1]
set_property -name {xsim.elaborate.debug_level} -value {typical} \
    -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
