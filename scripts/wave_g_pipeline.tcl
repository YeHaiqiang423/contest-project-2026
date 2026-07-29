# Run this in the XSim Tcl Console after opening tb_g_processing_pipeline_sim.
# The groups follow one sample through the complete pre-FFT pipeline.
add_wave_group "ADC input and 20 MSPS decimator"
add_wave /tb_g_processing_pipeline/clk
add_wave /tb_g_processing_pipeline/rst_n
add_wave /tb_g_processing_pipeline/capture_enable
add_wave -radix unsigned /tb_g_processing_pipeline/adc_data
add_wave /tb_g_processing_pipeline/adc_valid
add_wave /tb_g_processing_pipeline/dut/adc_sample_valid
add_wave -radix dec /tb_g_processing_pipeline/dut/adc_sample_data

add_wave_group "255-tap low-pass FIR"
add_wave /tb_g_processing_pipeline/dut/fir_output_valid
add_wave -radix dec /tb_g_processing_pipeline/dut/fir_output_data
add_wave /tb_g_processing_pipeline/adc_input_overrun

add_wave_group "2 MSPS frame capture"
add_wave /tb_g_processing_pipeline/dut/frame_ready
add_wave /tb_g_processing_pipeline/dut/frame_bank
add_wave -radix bin /tb_g_processing_pipeline/bank_pending
add_wave /tb_g_processing_pipeline/dut/capture_stalled
add_wave /tb_g_processing_pipeline/frame_overrun

add_wave_group "Hann and FFT input handshake"
add_wave /tb_g_processing_pipeline/dut/fft_start
add_wave /tb_g_processing_pipeline/dut/fft_busy
add_wave /tb_g_processing_pipeline/fft_valid
add_wave /tb_g_processing_pipeline/fft_ready
add_wave -radix dec /tb_g_processing_pipeline/fft_real
add_wave -radix dec /tb_g_processing_pipeline/fft_imag
add_wave /tb_g_processing_pipeline/fft_last
add_wave /tb_g_processing_pipeline/frame_done
add_wave /tb_g_processing_pipeline/scheduler_overrun
