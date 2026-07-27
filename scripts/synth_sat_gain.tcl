set project_root [file normalize [file join [file dirname [info script]] ..]]
set output_dir [file join $project_root results synth_sat_gain]
file mkdir $output_dir

read_verilog -sv [file join $project_root rtl src sat_gain.sv]
synth_design -top sat_gain -part xc7z020clg400-2
create_clock -name clk -period 20.000 [get_ports clk]

report_utilization -file [file join $output_dir utilization.rpt]
report_timing_summary -file [file join $output_dir timing_summary.rpt]
write_checkpoint -force [file join $output_dir post_synth.dcp]

puts "SYNTHESIS_COMPLETE: reports written to $output_dir"

