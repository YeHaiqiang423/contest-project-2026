set project_root [file normalize [file join [file dirname [info script]] ..]]
set build_dir [file join $project_root results board_ila_build]
set output_dir [file join $project_root results board_ila]
file mkdir $build_dir
file mkdir $output_dir
cd $project_root

create_project -force g_board_ila $build_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]

add_files [list \
    [file join $project_root rtl src adc_sample_frontend.v] \
    [file join $project_root rtl src g_symmetric_fir.v] \
    [file join $project_root rtl src g_frame_ram.v] \
    [file join $project_root rtl src g_frame_capture.v] \
    [file join $project_root rtl src g_hann_rom.v] \
    [file join $project_root rtl src g_fft_input_stream.v] \
    [file join $project_root rtl src g_integer_sqrt.v] \
    [file join $project_root rtl src g_unsigned_divider.v] \
    [file join $project_root rtl src g_uart_tx.v] \
    [file join $project_root rtl src g_uart_rx.v] \
    [file join $project_root rtl src g_binary_to_bcd.v] \
    [file join $project_root rtl src g_tjc_display_uart.v] \
    [file join $project_root rtl src g_fractional_divider.v] \
    [file join $project_root rtl src g_hann_amplitude_scaler.v] \
    [file join $project_root rtl src g_hann_peak_refiner.v] \
    [file join $project_root rtl src g_fft_core_wrapper.v] \
    [file join $project_root rtl src g_spectrum_analyzer.v] \
    [file join $project_root rtl src g_measurement_calibrator.v] \
    [file join $project_root rtl src g_processing_pipeline.v] \
    [file join $project_root rtl src g_board_ila_top.v]]
add_files -fileset constrs_1 [file join $project_root rtl constraints g_board_ila.xdc]
set_property top g_board_ila_top [current_fileset]

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
if {[llength [get_runs -quiet g_fft_4096_ip_synth_1]] == 0} {
    create_ip_run [get_files g_fft_4096_ip.xci]
}
launch_runs g_fft_4096_ip_synth_1 -jobs 2
wait_on_run g_fft_4096_ip_synth_1

create_ip -name ila -vendor xilinx.com -library ip -module_name board_ila
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {9} \
    CONFIG.C_PROBE0_WIDTH {14} \
    CONFIG.C_PROBE1_WIDTH {2} \
    CONFIG.C_PROBE2_WIDTH {20} \
    CONFIG.C_PROBE3_WIDTH {24} \
    CONFIG.C_PROBE4_WIDTH {20} \
    CONFIG.C_PROBE5_WIDTH {24} \
    CONFIG.C_PROBE6_WIDTH {24} \
    CONFIG.C_PROBE7_WIDTH {24} \
    CONFIG.C_PROBE8_WIDTH {16} \
    CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_INPUT_PIPE_STAGES {2} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_EN_STRG_QUAL {1}] [get_ips board_ila]
generate_target all [get_ips board_ila]
if {[llength [get_runs -quiet board_ila_synth_1]] == 0} {
    create_ip_run [get_files board_ila.xci]
}
launch_runs board_ila_synth_1 -jobs 2
wait_on_run board_ila_synth_1
update_compile_order -fileset sources_1

synth_design -top g_board_ila_top -part xc7z020clg400-2
write_checkpoint -force [file join $output_dir post_synth.dcp]
report_utilization -file [file join $output_dir utilization_synth.rpt]
report_timing_summary -report_unconstrained \
    -file [file join $output_dir timing_synth.rpt]
report_cdc -details -file [file join $output_dir cdc_synth.rpt]
check_timing -verbose -file [file join $output_dir check_timing_synth.rpt]

opt_design
place_design -directive ExtraPostPlacementOpt
phys_opt_design -directive AggressiveExplore
route_design -directive Explore

write_checkpoint -force [file join $output_dir post_route.dcp]
report_utilization -file [file join $output_dir utilization_route.rpt]
report_timing_summary -report_unconstrained \
    -file [file join $output_dir timing_route.rpt]
report_drc -file [file join $output_dir drc_route.rpt]
report_methodology -file [file join $output_dir methodology_route.rpt]
report_cdc -details -file [file join $output_dir cdc_route.rpt]
report_clock_interaction -file [file join $output_dir clock_interaction_route.rpt]
check_timing -verbose -file [file join $output_dir check_timing_route.rpt]

set worst_setup_path [get_timing_paths -delay_type max -max_paths 1]
set worst_hold_path [get_timing_paths -delay_type min -max_paths 1]
set setup_slack [get_property SLACK $worst_setup_path]
set hold_slack [get_property SLACK $worst_hold_path]
if {$setup_slack < 0.0} {
    error "BITSTREAM_GATE: negative setup slack $setup_slack ns"
}
if {$hold_slack < 0.0} {
    error "BITSTREAM_GATE: negative hold slack $hold_slack ns"
}

set check_timing_path [file join $output_dir check_timing_route.rpt]
set check_timing_handle [open $check_timing_path r]
set check_timing_text [read $check_timing_handle]
close $check_timing_handle
foreach pattern {
    {checking no_clock \(([1-9][0-9]*)\)}
    {checking unconstrained_internal_endpoints \(([1-9][0-9]*)\)}
    {There are ([1-9][0-9]*) input ports with no input delay specified\.}
    {There are ([1-9][0-9]*) output ports with no output delay specified\.}
} {
    if {[regexp $pattern $check_timing_text]} {
        error "BITSTREAM_GATE: check_timing reports an unconstrained object ($pattern)"
    }
}
set unconstrained_count 0

set cdc_path [file join $output_dir cdc_route.rpt]
set cdc_handle [open $cdc_path r]
set cdc_text [read $cdc_handle]
close $cdc_handle
if {[regexp {CDC-[0-9]+[ \t]+Critical[ \t]+[1-9][0-9]*} $cdc_text]} {
    error "BITSTREAM_GATE: report_cdc contains Critical crossings"
}

set drc_path [file join $output_dir drc_route.rpt]
set drc_handle [open $drc_path r]
set drc_text [read $drc_handle]
close $drc_handle
if {[regexp {\|[^|]+\|[ \t]*(Error|Critical Warning)[ \t]*\|} $drc_text]} {
    error "BITSTREAM_GATE: report_drc contains Error or Critical Warning violations"
}

write_bitstream -force [file join $output_dir g_board_ila.bit]
write_debug_probes -force [file join $output_dir g_board_ila.ltx]

set manifest [open [file join $output_dir build_manifest.txt] w]
puts $manifest "Vivado: [version -short]"
puts $manifest "Part: xc7z020clg400-2"
puts $manifest "Top: g_board_ila_top"
puts $manifest "Board clock: 50 MHz"
puts $manifest "ADC forward/system clock: 200 MHz"
puts $manifest "ADC data/return clock IOSTANDARD: HSTL_II_18"
puts $manifest "Bank 35 INTERNAL_VREF: 0.9 V"
puts $manifest "FFT: 4096-point natural-order 16-bit block floating point"
puts $manifest "FFT throttle scheme: Non-Realtime"
puts $manifest "Spectrum band: bins 20..1024 (10 kHz..500 kHz at 2 MSPS)"
puts $manifest "UART: W18 TX / W19 RX, LVCMOS33, 115200 8-N-1"
puts $manifest "Send button: PL KEY1 R19, active low, 20 ms debounce"
puts $manifest "Screen calibration command: ASCII C (0x43), 200000 uVpp reference"
puts $manifest "ILA depth: 4096 samples at 200 MHz"
puts $manifest "ILA probes: 9, calibration plus fundamental/harmonic physical values"
puts $manifest "Setup slack: $setup_slack ns"
puts $manifest "Hold slack: $hold_slack ns"
puts $manifest "Unconstrained paths: $unconstrained_count"
puts $manifest "Known limitation: ADC CLKOUT L20 uses CLOCK_DEDICATED_ROUTE FALSE."
puts $manifest "Known limitation: TI recommends external-clock CMOS capture above 150 MSPS."
close $manifest

puts "BOARD_ILA_BUILD_PASS: bitstream and probes written to $output_dir"
