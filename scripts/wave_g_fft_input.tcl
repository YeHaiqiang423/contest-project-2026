# Run this in the XSim Tcl Console after opening tb_g_fft_input_stream_sim.
add_wave /tb_g_fft_input_stream/clk
add_wave /tb_g_fft_input_stream/rst_n
add_wave /tb_g_fft_input_stream/start
add_wave /tb_g_fft_input_stream/start_bank
add_wave /tb_g_fft_input_stream/busy
add_wave /tb_g_fft_input_stream/frame_read_enable
add_wave /tb_g_fft_input_stream/frame_read_bank
add_wave /tb_g_fft_input_stream/frame_read_addr
add_wave /tb_g_fft_input_stream/frame_read_data
add_wave /tb_g_fft_input_stream/dut/read_pending
add_wave /tb_g_fft_input_stream/dut/sample_pending
add_wave -radix dec /tb_g_fft_input_stream/dut/sample_stage
add_wave -radix dec /tb_g_fft_input_stream/dut/coeff_stage
add_wave /tb_g_fft_input_stream/dut/multiply_pending
add_wave /tb_g_fft_input_stream/dut/window_coeff
add_wave /tb_g_fft_input_stream/dut/product_stage
add_wave /tb_g_fft_input_stream/fft_valid
add_wave /tb_g_fft_input_stream/fft_ready
add_wave /tb_g_fft_input_stream/fft_real
add_wave /tb_g_fft_input_stream/fft_imag
add_wave /tb_g_fft_input_stream/fft_last
add_wave /tb_g_fft_input_stream/release_valid
add_wave /tb_g_fft_input_stream/release_bank
