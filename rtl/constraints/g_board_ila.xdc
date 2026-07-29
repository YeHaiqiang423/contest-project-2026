# Mizar Z7 / xc7z020clg400-2 direct-plug ADC0 constraints.
# Pin assignments and I/O standards are copied from the supplied AD_DA_Test
# reference project. Only ADC0 is enabled by this validation top.

set_property PACKAGE_PIN H16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -name board_clk_50m -period 20.000 [get_ports clk]

set_property PACKAGE_PIN B19 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]
set_false_path -from [get_ports rst_n]

set_property PACKAGE_PIN L19 [get_ports adc0_clk_out]
set_property IOSTANDARD LVCMOS33 [get_ports adc0_clk_out]
set_property DRIVE 16 [get_ports adc0_clk_out]
set_property SLEW SLOW [get_ports adc0_clk_out]
set_property OFFCHIP_TERM NONE [get_ports adc0_clk_out]

set_property PACKAGE_PIN L20 [get_ports adc0_clk_in]
set_property IOSTANDARD HSTL_II_18 [get_ports adc0_clk_in]
set_property OFFCHIP_TERM NONE [get_ports adc0_clk_in]

set_property INTERNAL_VREF 0.9 [get_iobanks 35]

set_property PACKAGE_PIN K19 [get_ports {adc0_data[13]}]
set_property PACKAGE_PIN J19 [get_ports {adc0_data[12]}]
set_property PACKAGE_PIN L14 [get_ports {adc0_data[11]}]
set_property PACKAGE_PIN L15 [get_ports {adc0_data[10]}]
set_property PACKAGE_PIN J20 [get_ports {adc0_data[9]}]
set_property PACKAGE_PIN H20 [get_ports {adc0_data[8]}]
set_property PACKAGE_PIN H15 [get_ports {adc0_data[7]}]
set_property PACKAGE_PIN G15 [get_ports {adc0_data[6]}]
set_property PACKAGE_PIN K14 [get_ports {adc0_data[5]}]
set_property PACKAGE_PIN J14 [get_ports {adc0_data[4]}]
set_property PACKAGE_PIN G17 [get_ports {adc0_data[3]}]
set_property PACKAGE_PIN G18 [get_ports {adc0_data[2]}]
set_property PACKAGE_PIN J18 [get_ports {adc0_data[1]}]
set_property PACKAGE_PIN H18 [get_ports {adc0_data[0]}]
set_property IOSTANDARD HSTL_II_18 [get_ports {adc0_data[*]}]
set_property OFFCHIP_TERM NONE [get_ports {adc0_data[*]}]

# The supplied PCB routes ADS6149 CLKOUT to L20, which cannot use a dedicated
# IO-to-BUFG route. This override is confined to the return-clock capture/FIFO
# domain and is an acknowledged limitation of the reference hardware mapping.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets adc_return_clk_ibuf]
create_clock -name adc_return_clk -period 5.000 [get_ports adc0_clk_in]

# Provisional source-synchronous limits for the initial ILA image. TI does not
# specify parallel-CMOS CLKOUT setup/hold at 200 MSPS and recommends external-
# clock capture above 150 MSPS. Negative max models data becoming valid at
# least 1.0 ns before CLKOUT; positive min models data remaining valid for at
# least 0.4 ns after CLKOUT. ILA phase/error testing remains mandatory.
set_input_delay -clock adc_return_clk -max -1.000 [get_ports {adc0_data[*]}]
set_input_delay -clock adc_return_clk -min 0.400 [get_ports {adc0_data[*]}]

# Treat the off-chip-returned clock and the clean MMCM clock as asynchronous at
# the FIFO boundary. XPM_FIFO_ASYNC supplies the required internal CDC rules.
set adc_return_clock_object [get_clocks adc_return_clk]
set system_clock_object [get_clocks -of_objects [get_pins system_clock_buffer/O]]
set_clock_groups -asynchronous \
    -group $adc_return_clock_object \
    -group $system_clock_object

# adc0_clk_out is a forwarded clock rather than a normal data output.
create_generated_clock -name adc_forward_clk \
    -source [get_pins system_clock_buffer/O] \
    -divide_by 1 [get_ports adc0_clk_out]
