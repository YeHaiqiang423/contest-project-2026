# Run this in the XSim Tcl Console after opening tb_g_symmetric_fir_sim.
add_wave /tb_g_symmetric_fir/clk
add_wave /tb_g_symmetric_fir/rst_n
add_wave /tb_g_symmetric_fir/sample_valid
add_wave /tb_g_symmetric_fir/sample_data
add_wave /tb_g_symmetric_fir/dut/active
add_wave /tb_g_symmetric_fir/dut/phase
add_wave /tb_g_symmetric_fir/dut/valid_select
add_wave /tb_g_symmetric_fir/dut/valid_pair
add_wave /tb_g_symmetric_fir/dut/valid_product
add_wave /tb_g_symmetric_fir/dut/tag_level4
add_wave /tb_g_symmetric_fir/dut/accumulator
add_wave /tb_g_symmetric_fir/dut/final_sum
add_wave /tb_g_symmetric_fir/output_valid
add_wave /tb_g_symmetric_fir/output_data
add_wave /tb_g_symmetric_fir/input_overrun
