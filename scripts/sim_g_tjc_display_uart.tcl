set project_root [file normalize [file join [file dirname [info script]] ..]]
set gui_mode [expr {[llength $argv] > 0 && [lindex $argv 0] eq "gui"}]
set build_dir [file join $project_root results g_tjc_display_uart_sim]
create_project -force g_tjc_display_uart_sim $build_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files [list \
    [file join $project_root rtl src g_uart_tx.v] \
    [file join $project_root rtl src g_uart_rx.v] \
    [file join $project_root rtl src g_binary_to_bcd.v] \
    [file join $project_root rtl src g_tjc_display_uart.v]]
add_files -fileset sim_1 [file join $project_root rtl tb tb_g_tjc_display_uart.sv]
set_property top tb_g_tjc_display_uart [get_filesets sim_1]
set_property -name {xsim.elaborate.debug_level} -value {typical} \
    -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
if {$gui_mode} {
    source [file join $project_root scripts wave_g_tjc_display_uart.tcl]
    puts "TJC_UART_GUI_READY: use Run All"
    return
}
run all
close_sim
close_project

