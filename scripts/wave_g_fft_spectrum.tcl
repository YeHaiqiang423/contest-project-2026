set tb /tb_g_fft_spectrum
add_wave_group "FFT input handshake"
add_wave $tb/input_valid $tb/input_ready $tb/input_real $tb/input_last
add_wave_group "FFT natural-order output"
add_wave $tb/fft_output_valid $tb/fft_output_ready
add_wave $tb/fft_output_bin $tb/fft_output_real $tb/fft_output_imag
add_wave $tb/fft_output_block_exponent $tb/fft_output_last
add_wave_group "Spectrum power"
add_wave $tb/spectrum_valid $tb/spectrum_bin $tb/spectrum_power
add_wave_group "Locked measurement results"
add_wave $tb/results_valid $tb/component_count
add_wave $tb/fundamental_bin $tb/fundamental_frequency_hz
add_wave $tb/peak0_bin $tb/peak1_bin $tb/peak2_bin
add_wave $tb/peak0_frequency_hz $tb/peak1_frequency_hz
add_wave $tb/peak2_frequency_hz
add_wave $tb/peak0_amplitude_code $tb/peak1_amplitude_code
add_wave $tb/peak2_amplitude_code $tb/result_block_exponent
add_wave_group "Calibrated UART handoff"
add_wave $tb/measurement_valid $tb/measurement_component_count
add_wave $tb/component0_frequency_hz $tb/component0_amplitude_uv
add_wave $tb/component0_rms_uv
add_wave $tb/component1_frequency_hz $tb/component1_amplitude_uv
add_wave $tb/component1_rms_uv
add_wave $tb/component2_frequency_hz $tb/component2_amplitude_uv
add_wave $tb/component2_rms_uv $tb/total_true_rms_uv
add_wave_group "Protocol health"
add_wave $tb/fft_configured $tb/fft_frame_started $tb/fft_error_sticky
