set project_root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint [file join $project_root results board_ila post_route.dcp]
report_timing -delay_type max -max_paths 100 -nworst 1 \
    -slack_lesser_than 0.0 -file \
    [file join $project_root results board_ila timing_violations_100.rpt]
puts "TIMING_VIOLATION_REPORT_WRITTEN"
