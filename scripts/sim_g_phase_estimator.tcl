set project_root [file normalize [file join [file dirname [info script]] ..]]
set build_dir [file join $project_root results g_phase_estimator_sim]
create_project -force g_phase_estimator_sim $build_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files [list \
    [file join $project_root rtl src g_frame_ram.v] \
    [file join $project_root rtl src g_unsigned_divider.v] \
    [file join $project_root rtl src g_sine_cos_rom.v] \
    [file join $project_root rtl src g_cordic_atan2.v] \
    [file join $project_root rtl src g_phase_estimator.v]]
add_files -fileset sim_1 [file join $project_root rtl tb tb_g_phase_estimator.sv]
set_property top tb_g_phase_estimator [get_filesets sim_1]
set phase_input [file normalize [file join $project_root matlab vectors g_phase_input.txt]]
set phase_config [file normalize [file join $project_root matlab vectors g_phase_config.txt]]
set phase_expected [file normalize [file join $project_root matlab vectors g_phase_expected.txt]]
set sine_file [file normalize [file join $project_root matlab vectors g_sine_q15_4096.hex]]
set_property generic "SINE_FILE=$sine_file" [get_filesets sim_1]
set_property -name {xsim.simulate.xsim.more_options} \
    -value "-testplusarg PHASE_INPUT=$phase_input -testplusarg PHASE_CONFIG=$phase_config -testplusarg PHASE_EXPECTED=$phase_expected" \
    -objects [get_filesets sim_1]
set_property -name {xsim.elaborate.debug_level} -value {typical} \
    -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
