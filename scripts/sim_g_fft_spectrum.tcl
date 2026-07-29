set project_root [file normalize [file join [file dirname [info script]] ..]]
set gui_mode [expr {[llength $argv] > 0 && [lindex $argv 0] eq "gui"}]
set build_dir [file join $project_root results g_fft_spectrum_sim]
create_project -force g_fft_spectrum_sim $build_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files [list \
    [file join $project_root rtl src g_integer_sqrt.v] \
    [file join $project_root rtl src g_fractional_divider.v] \
    [file join $project_root rtl src g_hann_amplitude_scaler.v] \
    [file join $project_root rtl src g_hann_peak_refiner.v] \
    [file join $project_root rtl src g_fft_core_wrapper.v] \
    [file join $project_root rtl src g_spectrum_analyzer.v]]
add_files -fileset sim_1 [file join $project_root rtl tb tb_g_fft_spectrum.sv]
set_property top tb_g_fft_spectrum [get_filesets sim_1]

create_ip -name xfft -vendor xilinx.com -library ip -module_name g_fft_4096_ip
set_property -dict [list \
    CONFIG.transform_length {4096} \
    CONFIG.implementation_options {radix_2_lite_burst_io} \
    CONFIG.input_width {16} \
    CONFIG.phase_factor_width {16} \
    CONFIG.scaling_options {block_floating_point} \
    CONFIG.rounding_modes {convergent_rounding} \
    CONFIG.throttle_scheme {nonrealtime} \
    CONFIG.output_ordering {natural_order} \
    CONFIG.xk_index {true} \
    CONFIG.aresetn {true} \
    CONFIG.target_clock_frequency {200}] [get_ips g_fft_4096_ip]
generate_target all [get_ips g_fft_4096_ip]

set vector_path [file normalize [file join $project_root matlab vectors g_fft_spectrum_input.txt]]
set_property -name {xsim.simulate.xsim.more_options} \
    -value "-testplusarg VECTOR_FILE=$vector_path" -objects [get_filesets sim_1]
set_property -name {xsim.elaborate.debug_level} -value {typical} \
    -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
if {$gui_mode} {
    source [file join $project_root scripts wave_g_fft_spectrum.tcl]
    puts "FFT_SPECTRUM_GUI_READY: use Run All to execute the self-check"
    return
}
run all
close_sim
close_project
