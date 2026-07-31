set project_root [file normalize [file join [file dirname [info script]] ..]]
set bit_file [file join $project_root results board_ila g_board_release.bit]

if {![file exists $bit_file]} {
    error "Bitstream not found: $bit_file"
}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set zynq_devices {}
foreach device [get_hw_devices] {
    if {[string match "*xc7z020*" [string tolower [get_property PART $device]]]} {
        lappend zynq_devices $device
    }
}

if {[llength $zynq_devices] != 1} {
    error "Expected exactly one xc7z020 target, found [llength $zynq_devices]: $zynq_devices"
}

set target_device [lindex $zynq_devices 0]
current_hw_device $target_device
set_property PROGRAM.FILE $bit_file $target_device
program_hw_devices $target_device
refresh_hw_device $target_device

puts "BOARD_RELEASE_PROGRAM_PASS: programmed $target_device without ILA probes"
puts "Bitstream: $bit_file"
