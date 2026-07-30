set tb /tb_g_measurement_calibrator
add_wave_group "Virtual spectrum input"
add_wave $tb/spectrum_results_valid $tb/component_count_in
add_wave $tb/peak0_frequency_hz $tb/peak0_amplitude_code
add_wave $tb/peak1_frequency_hz $tb/peak1_amplitude_code
add_wave $tb/peak2_frequency_hz $tb/peak2_amplitude_code
add_wave_group "Calibration trigger"
add_wave $tb/gain_write $tb/gain_write_q16
add_wave $tb/calibrate_start $tb/calibration_reference_vpp_uv
add_wave $tb/active_gain_q16 $tb/calibration_busy
add_wave $tb/calibration_done $tb/calibration_error
add_wave_group "UART handoff"
add_wave $tb/measurement_valid $tb/measurement_overrun
add_wave $tb/component_count
add_wave $tb/component0_frequency_hz $tb/component0_amplitude_uv
add_wave $tb/component0_rms_uv
add_wave $tb/component1_frequency_hz $tb/component1_amplitude_uv
add_wave $tb/component1_rms_uv
add_wave $tb/component2_frequency_hz $tb/component2_amplitude_uv
add_wave $tb/component2_rms_uv $tb/total_true_rms_uv
