set project_root [file normalize [file join [file dirname [info script]] ..]]
set source_dcp [file join $project_root results board_ila post_route.dcp]
set output_dir [file join $project_root results board_ila provisional]
file mkdir $output_dir

open_checkpoint $source_dcp

set worst_setup_path [get_timing_paths -delay_type max -max_paths 1]
set worst_hold_path [get_timing_paths -delay_type min -max_paths 1]
set setup_slack [get_property SLACK $worst_setup_path]
set hold_slack [get_property SLACK $worst_hold_path]

# This exporter is deliberately separate from the sign-off build.  It permits
# only the already-reviewed small setup miss so that hardware characterization
# can proceed while the normal build continues to require non-negative slack.
if {$setup_slack < -0.150} {
    error "PROVISIONAL_GATE: setup slack $setup_slack ns is below -0.150 ns"
}
if {$hold_slack < 0.0} {
    error "PROVISIONAL_GATE: negative hold slack $hold_slack ns"
}

set bit_path [file join $output_dir g_board_ila_provisional.bit]
set ltx_path [file join $output_dir g_board_ila_provisional.ltx]
write_bitstream -force $bit_path
write_debug_probes -force $ltx_path

set manifest [open [file join $output_dir PROVISIONAL_README.txt] w]
puts $manifest "NON-SIGN-OFF HARDWARE TEST IMAGE"
puts $manifest "Source checkpoint: $source_dcp"
puts $manifest "Setup slack: $setup_slack ns"
puts $manifest "Hold slack: $hold_slack ns"
puts $manifest "Limit: use only for bench characterization; replace after timing closure."
close $manifest

puts "PROVISIONAL_EXPORT_PASS: setup=$setup_slack ns hold=$hold_slack ns"
