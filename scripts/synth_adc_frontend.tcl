set project_root [file normalize [file join [file dirname [info script]] ..]]
set output_dir [file join $project_root results synth_adc_frontend]
file mkdir $output_dir

read_verilog [file join $project_root rtl src adc_sample_frontend.v]
synth_design -top adc_sample_frontend -part xc7z020clg400-2 \
    -generic ADC_WIDTH=14 -generic DECIMATION=10 -generic INPUT_OFFSET_BINARY=0
create_clock -name clk_adc -period 5.000 [get_ports clk_adc]

report_utilization -file [file join $output_dir utilization.rpt]
report_timing_summary -file [file join $output_dir timing_summary.rpt]
write_checkpoint -force [file join $output_dir post_synth.dcp]
puts "SYNTHESIS_COMPLETE: reports written to $output_dir"
