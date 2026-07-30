set tb /tb_g_tjc_display_uart
add_wave_group "Button and UART"
add_wave $tb/send_button_n $tb/send_button_pressed
add_wave $tb/uart_rx $tb/uart_tx $tb/tx_busy
add_wave $tb/calibrate_start $tb/rx_calibrate_command
add_wave_group "Measurement input"
add_wave $tb/measurement_valid $tb/component_count
add_wave $tb/component0_frequency_hz $tb/component0_amplitude_uv
add_wave $tb/component1_frequency_hz $tb/component1_amplitude_uv
add_wave_group "Internal command sequencer"
add_wave $tb/dut/field_index $tb/dut/character_index
add_wave $tb/dut/tx_start $tb/dut/tx_data

