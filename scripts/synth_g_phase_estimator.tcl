set project_root [file normalize [file join [file dirname [info script]] ..]]
set output_dir [file join $project_root results synth_g_phase_estimator]
file mkdir $output_dir
cd $project_root

read_verilog [file join $project_root rtl src g_frame_ram.v]
read_verilog [file join $project_root rtl src g_unsigned_divider.v]
read_verilog [file join $project_root rtl src g_sine_cos_rom.v]
read_verilog [file join $project_root rtl src g_cordic_atan2.v]
read_verilog [file join $project_root rtl src g_phase_estimator.v]
synth_design -top g_phase_estimator -mode out_of_context \
    -part xc7z020clg400-2
create_clock -name clk -period 5.000 [get_ports clk]

report_utilization -file [file join $output_dir utilization.rpt]
report_timing_summary -file [file join $output_dir timing_summary.rpt]
write_checkpoint -force [file join $output_dir post_synth.dcp]
puts "SYNTHESIS_COMPLETE: phase estimator reports written to $output_dir"
