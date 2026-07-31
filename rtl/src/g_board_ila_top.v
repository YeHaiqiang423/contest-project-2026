`timescale 1ns/1ps

// Initial board-validation top for Mizar Z7 + direct-plug ADS6149 module.
// The ADS6149 CLKOUT capture path intentionally follows the vendor reference
// design. It is isolated from the 200 MHz algorithm clock by an XPM async FIFO.
module g_board_ila_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        send_button_n,
    input  wire [13:0] adc0_data,
    input  wire        adc0_clk_in,
    output wire        adc0_clk_out,
    input  wire        uart_rx,
    output wire        uart_tx
);

    wire clk_50_ibuf;
    wire clk_feedback;
    wire clk_feedback_buf;
    wire clk_200_mmcm;
    wire clk_200;
    wire mmcm_locked;
    wire adc_return_clk_ibuf;
    wire adc_return_clk;

    wire system_rst_n;
    wire adc_return_rst_n;
    (* max_fanout = 64 *) reg measurement_rst_n;
    (* max_fanout = 64 *) reg pipeline_rst_n;
    (* max_fanout = 64 *) reg fft_rst_n;
    (* max_fanout = 64 *) reg analyzer_rst_n;
    (* max_fanout = 64 *) reg time_display_rst_n;
    (* max_fanout = 64 *) reg spectrum_display_rst_n;
    (* max_fanout = 64 *) reg screen_rst_n;

    (* IOB = "TRUE" *) reg [13:0] adc_iob_data;

    wire [13:0] fifo_dout;
    wire fifo_full;
    wire fifo_empty;
    wire fifo_overflow;
    wire fifo_underflow;
    wire fifo_wr_rst_busy;
    wire fifo_rd_rst_busy;
    wire fifo_data_valid;
    wire fifo_write_enable;
    wire fifo_read_enable;
    wire [10:0] fifo_read_count;
    reg fifo_overflow_sticky;
    reg fifo_read_started;
    reg [4:0] fifo_status_wr;
    wire [4:0] fifo_status_sync;
    wire fifo_reset;

    wire adc_stream_valid;
    wire fft_valid;
    wire signed [15:0] fft_real;
    wire signed [15:0] fft_imag;
    wire fft_last;
    wire frame_done;
    wire [1:0] bank_pending;
    wire adc_input_overrun;
    wire frame_overrun;
    wire scheduler_overrun;
    wire debug_adc_sample_valid;
    wire signed [13:0] debug_adc_sample_data;
    wire debug_fir_output_valid;
    wire signed [15:0] debug_fir_output_data;
    wire debug_frame_ready;
    wire debug_frame_bank;
    wire debug_fft_busy;

    wire fft_input_ready;
    wire fft_output_valid;
    wire fft_output_ready;
    wire signed [15:0] fft_output_real;
    wire signed [15:0] fft_output_imag;
    wire [11:0] fft_output_bin;
    wire [4:0] fft_output_block_exponent;
    wire fft_output_last;
    wire fft_frame_started;
    wire fft_configured;
    wire [4:0] fft_error_sticky;
    wire spectrum_valid;
    wire [11:0] spectrum_bin;
    wire [32:0] spectrum_power;
    wire [4:0] spectrum_block_exponent;
    wire spectrum_results_valid;
    wire [1:0] component_count;
    wire [11:0] fundamental_bin;
    wire [19:0] fundamental_frequency_hz;
    wire [11:0] peak0_bin;
    wire [11:0] peak1_bin;
    wire [11:0] peak2_bin;
    wire [19:0] peak0_frequency_hz;
    wire [19:0] peak1_frequency_hz;
    wire [19:0] peak2_frequency_hz;
    wire [32:0] peak0_power;
    wire [32:0] peak1_power;
    wire [32:0] peak2_power;
    wire [15:0] peak0_amplitude_code;
    wire [15:0] peak1_amplitude_code;
    wire [15:0] peak2_amplitude_code;
    wire [4:0] result_block_exponent;

    // UART handoff interface. Values are sorted by ascending frequency;
    // amplitude is sine peak voltage and all voltage quantities use uV.
    wire [23:0] calibration_gain_q16;
    wire calibration_busy;
    wire calibration_done;
    wire calibration_error;
    wire calibrated_measurement_valid;
    wire measurement_overrun;
    wire [1:0] calibrated_component_count;
    wire [19:0] calibrated_component0_frequency_hz;
    wire [19:0] calibrated_component1_frequency_hz;
    wire [19:0] calibrated_component2_frequency_hz;
    wire [23:0] calibrated_component0_amplitude_uv;
    wire [23:0] calibrated_component1_amplitude_uv;
    wire [23:0] calibrated_component2_amplitude_uv;
    wire [23:0] component0_rms_uv;
    wire [23:0] component1_rms_uv;
    wire [23:0] component2_rms_uv;
    wire [23:0] calibrated_total_true_rms_uv;
    wire measurement_valid;
    wire measurement_stable;
    wire [1:0] measurement_component_count;
    wire [19:0] component0_frequency_hz;
    wire [19:0] component1_frequency_hz;
    wire [19:0] component2_frequency_hz;
    wire [23:0] component0_amplitude_uv;
    wire [23:0] component1_amplitude_uv;
    wire [23:0] component2_amplitude_uv;
    wire [23:0] total_true_rms_uv;
    wire total_vpp_valid;
    wire [15:0] total_vpp_code;
    wire [23:0] total_vpp_uv;
    wire waveform_display_ready;
    wire waveform_render_busy;
    wire waveform_render_done;
    wire waveform_request_overrun;
    wire [7:0] waveform_display_data;
    wire spectrum_display_ready;
    wire spectrum_display_done;
    wire spectrum_display_busy;
    wire spectrum_display_overrun;
    wire [7:0] spectrum_display_data;
    wire [9:0] display_read_addr;
    wire waveform_render_request;
    wire uart_three_cycle_mode;
    wire uart_spectrum_mode;

    wire calibrate_start_uart;
    wire [23:0] calibration_reference_vpp_uv;
    wire uart_rx_calibrate_command;
    wire uart_rx_framing_error_sticky;
    wire uart_send_button_pressed;
    wire uart_tx_busy;
    wire uart_transfer_busy;
    wire uart_transfer_done;
    wire uart_transparent_timeout;
    wire uart_request_overrun;

    IBUF clock_input_buffer (
        .I(clk),
        .O(clk_50_ibuf)
    );

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(20.000),
        .CLKIN1_PERIOD(20.000),
        .CLKOUT0_DIVIDE_F(5.000),
        .DIVCLK_DIVIDE(1),
        .STARTUP_WAIT("FALSE")
    ) system_mmcm (
        .CLKIN1(clk_50_ibuf),
        .CLKFBIN(clk_feedback_buf),
        .RST(~rst_n),
        .PWRDWN(1'b0),
        .CLKFBOUT(clk_feedback),
        .CLKOUT0(clk_200_mmcm),
        .LOCKED(mmcm_locked),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
    );

    BUFG feedback_clock_buffer (
        .I(clk_feedback),
        .O(clk_feedback_buf)
    );

    BUFG system_clock_buffer (
        .I(clk_200_mmcm),
        .O(clk_200)
    );

    // The same clean 200 MHz clock is forwarded to the ADC sampling-clock pin.
    assign adc0_clk_out = clk_200;

    IBUF adc_return_clock_input_buffer (
        .I(adc0_clk_in),
        .O(adc_return_clk_ibuf)
    );

    BUFG adc_return_clock_buffer (
        .I(adc_return_clk_ibuf),
        .O(adc_return_clk)
    );

    // XPM reset synchronizers provide asynchronous assertion and synchronous
    // release independently in both clock domains.
    xpm_cdc_async_rst #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .RST_ACTIVE_HIGH(0)
    ) system_reset_synchronizer (
        .src_arst(rst_n & mmcm_locked),
        .dest_clk(clk_200),
        .dest_arst(system_rst_n)
    );

    xpm_cdc_async_rst #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .RST_ACTIVE_HIGH(0)
    ) adc_reset_synchronizer (
        .src_arst(rst_n & mmcm_locked),
        .dest_clk(adc_return_clk),
        .dest_arst(adc_return_rst_n)
    );

    // Local reset replicas keep the synchronizer output off the thousands of
    // reset muxes added by the measurement/display subsystem.  Assertion and
    // release are still synchronous to clk_200, delayed by one clock only.
    always @(posedge clk_200) begin
        if (!system_rst_n) begin
            measurement_rst_n <= 1'b0;
            pipeline_rst_n <= 1'b0;
            fft_rst_n <= 1'b0;
            analyzer_rst_n <= 1'b0;
            time_display_rst_n <= 1'b0;
            spectrum_display_rst_n <= 1'b0;
            screen_rst_n <= 1'b0;
        end else begin
            measurement_rst_n <= 1'b1;
            pipeline_rst_n <= 1'b1;
            fft_rst_n <= 1'b1;
            analyzer_rst_n <= 1'b1;
            time_display_rst_n <= 1'b1;
            spectrum_display_rst_n <= 1'b1;
            screen_rst_n <= 1'b1;
        end
    end

    always @(posedge adc_return_clk) begin
        if (!adc_return_rst_n)
            adc_iob_data <= 14'd0;
        else
            adc_iob_data <= adc0_data;
    end

    assign fifo_write_enable = adc_return_rst_n && !fifo_full && !fifo_wr_rst_busy;
    assign fifo_read_enable = system_rst_n && fifo_read_started &&
        !fifo_empty && !fifo_rd_rst_busy;
    // XPM_FIFO_ASYNC requires its reset to be synchronous to wr_clk.
    assign fifo_reset = ~adc_return_rst_n;

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("block"),
        .ECC_MODE("no_ecc"),
        .RELATED_CLOCKS(0),
        .FIFO_WRITE_DEPTH(1024),
        .WRITE_DATA_WIDTH(14),
        .WR_DATA_COUNT_WIDTH(11),
        .PROG_FULL_THRESH(1000),
        .FULL_RESET_VALUE(0),
        // 0x1000 explicitly enables data_valid; 0x0707 keeps the FIFO
        // overflow/count/prog-empty features used by this bridge.
        .USE_ADV_FEATURES("1707"),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .READ_DATA_WIDTH(14),
        .RD_DATA_COUNT_WIDTH(11),
        .PROG_EMPTY_THRESH(10),
        .DOUT_RESET_VALUE("0"),
        .CDC_SYNC_STAGES(2),
        .WAKEUP_TIME(0)
    ) adc_clock_crossing_fifo (
        .sleep(1'b0),
        .rst(fifo_reset),
        .wr_clk(adc_return_clk),
        .wr_en(fifo_write_enable),
        .din(adc_iob_data),
        .full(fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(fifo_overflow),
        .wr_rst_busy(fifo_wr_rst_busy),
        .almost_full(),
        .wr_ack(),
        .rd_clk(clk_200),
        .rd_en(fifo_read_enable),
        .dout(fifo_dout),
        .empty(fifo_empty),
        .prog_empty(),
        .rd_data_count(fifo_read_count),
        .underflow(fifo_underflow),
        .rd_rst_busy(fifo_rd_rst_busy),
        .almost_empty(),
        .data_valid(fifo_data_valid),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr()
    );

    // The write/read clocks are nominally equal but phase-shifted by the ADC
    // and PCB. Pre-fill the FIFO before draining it so pointer synchronizer
    // latency cannot create periodic valid gaps at an almost-empty boundary.
    always @(posedge clk_200) begin
        if (!system_rst_n)
            fifo_read_started <= 1'b0;
        else if (fifo_read_count >= 11'd16)
            fifo_read_started <= 1'b1;
    end

    always @(posedge adc_return_clk) begin
        if (!adc_return_rst_n) begin
            fifo_overflow_sticky <= 1'b0;
            fifo_status_wr <= 5'b00000;
        end else begin
            if (fifo_overflow)
                fifo_overflow_sticky <= 1'b1;
            fifo_status_wr <= {
                adc_return_rst_n,
                fifo_wr_rst_busy,
                fifo_overflow_sticky | fifo_overflow,
                fifo_overflow,
                fifo_full
            };
        end
    end

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(2),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(0),
        .WIDTH(5)
    ) fifo_status_cdc (
        .src_clk(adc_return_clk),
        .src_in(fifo_status_wr),
        .dest_clk(clk_200),
        .dest_out(fifo_status_sync)
    );

    assign adc_stream_valid = fifo_data_valid && fifo_read_enable;

    g_processing_pipeline #(
        .ADC_OFFSET_BINARY(0)
    ) processing_pipeline (
        .clk(clk_200),
        .rst_n(pipeline_rst_n),
        .capture_enable(1'b1),
        .adc_valid(adc_stream_valid),
        .adc_data(fifo_dout),
        .fft_ready(fft_input_ready),
        .fft_valid(fft_valid),
        .fft_real(fft_real),
        .fft_imag(fft_imag),
        .fft_last(fft_last),
        .frame_done(frame_done),
        .bank_pending(bank_pending),
        .adc_input_overrun(adc_input_overrun),
        .frame_overrun(frame_overrun),
        .scheduler_overrun(scheduler_overrun),
        .debug_adc_sample_valid(debug_adc_sample_valid),
        .debug_adc_sample_data(debug_adc_sample_data),
        .debug_fir_output_valid(debug_fir_output_valid),
        .debug_fir_output_data(debug_fir_output_data),
        .debug_frame_ready(debug_frame_ready),
        .debug_frame_bank(debug_frame_bank),
        .debug_fft_busy(debug_fft_busy)
    );

    g_fft_core_wrapper fft_wrapper (
        .clk(clk_200), .rst_n(fft_rst_n),
        .input_valid(fft_valid), .input_ready(fft_input_ready),
        .input_real(fft_real), .input_imag(fft_imag),
        .input_last(fft_last), .output_valid(fft_output_valid),
        .output_ready(fft_output_ready), .output_real(fft_output_real),
        .output_imag(fft_output_imag), .output_bin(fft_output_bin),
        .output_block_exponent(fft_output_block_exponent),
        .output_last(fft_output_last), .frame_started(fft_frame_started),
        .configured(fft_configured), .error_sticky(fft_error_sticky)
    );

    g_spectrum_analyzer spectrum_analyzer (
        .clk(clk_200), .rst_n(analyzer_rst_n),
        .fft_valid(fft_output_valid), .fft_ready(fft_output_ready),
        .fft_real(fft_output_real), .fft_imag(fft_output_imag),
        .fft_bin(fft_output_bin),
        .fft_block_exponent(fft_output_block_exponent),
        .fft_last(fft_output_last), .spectrum_valid(spectrum_valid),
        .spectrum_bin(spectrum_bin), .spectrum_power(spectrum_power),
        .spectrum_block_exponent(spectrum_block_exponent),
        .results_valid(spectrum_results_valid),
        .component_count(component_count), .fundamental_bin(fundamental_bin),
        .fundamental_frequency_hz(fundamental_frequency_hz),
        .peak0_bin(peak0_bin), .peak1_bin(peak1_bin), .peak2_bin(peak2_bin),
        .peak0_frequency_hz(peak0_frequency_hz),
        .peak1_frequency_hz(peak1_frequency_hz),
        .peak2_frequency_hz(peak2_frequency_hz),
        .peak0_power(peak0_power), .peak1_power(peak1_power),
        .peak2_power(peak2_power),
        .peak0_amplitude_code(peak0_amplitude_code),
        .peak1_amplitude_code(peak1_amplitude_code),
        .peak2_amplitude_code(peak2_amplitude_code),
        .result_block_exponent(result_block_exponent)
    );

    // Field calibration is initiated by the TJC screen sending ASCII 'C'.
    // The reference is fixed to the documented 200 mVpp calibration sine.
    g_measurement_calibrator measurement_calibrator (
        .clk(clk_200), .rst_n(measurement_rst_n),
        .spectrum_results_valid(spectrum_results_valid),
        .component_count_in(component_count),
        .peak0_frequency_hz(peak0_frequency_hz),
        .peak1_frequency_hz(peak1_frequency_hz),
        .peak2_frequency_hz(peak2_frequency_hz),
        .peak0_amplitude_code(peak0_amplitude_code),
        .peak1_amplitude_code(peak1_amplitude_code),
        .peak2_amplitude_code(peak2_amplitude_code),
        .gain_write(1'b0), .gain_write_q16(24'd0),
        .calibrate_start(calibrate_start_uart),
        .calibration_reference_vpp_uv(calibration_reference_vpp_uv),
        .active_gain_q16(calibration_gain_q16),
        .calibration_busy(calibration_busy),
        .calibration_done(calibration_done),
        .calibration_error(calibration_error),
        .measurement_valid(calibrated_measurement_valid),
        .measurement_overrun(measurement_overrun),
        .component_count(calibrated_component_count),
        .component0_frequency_hz(calibrated_component0_frequency_hz),
        .component1_frequency_hz(calibrated_component1_frequency_hz),
        .component2_frequency_hz(calibrated_component2_frequency_hz),
        .component0_amplitude_uv(calibrated_component0_amplitude_uv),
        .component1_amplitude_uv(calibrated_component1_amplitude_uv),
        .component2_amplitude_uv(calibrated_component2_amplitude_uv),
        .component0_rms_uv(component0_rms_uv),
        .component1_rms_uv(component1_rms_uv),
        .component2_rms_uv(component2_rms_uv),
        .total_true_rms_uv(calibrated_total_true_rms_uv)
    );

    // Only publish two consecutive, mutually consistent frames.  This removes
    // source switching transients from the visible result while adding about
    // 2.048 ms, far below the contest's two-second limit.
    g_measurement_stabilizer measurement_stabilizer (
        .clk(clk_200), .rst_n(measurement_rst_n),
        .measurement_valid(calibrated_measurement_valid),
        .component_count_in(calibrated_component_count),
        .component0_frequency_hz_in(calibrated_component0_frequency_hz),
        .component1_frequency_hz_in(calibrated_component1_frequency_hz),
        .component2_frequency_hz_in(calibrated_component2_frequency_hz),
        .component0_amplitude_uv_in(calibrated_component0_amplitude_uv),
        .component1_amplitude_uv_in(calibrated_component1_amplitude_uv),
        .component2_amplitude_uv_in(calibrated_component2_amplitude_uv),
        .total_true_rms_uv_in(calibrated_total_true_rms_uv),
        .stable_valid(measurement_valid),
        .stable_locked(measurement_stable),
        .component_count(measurement_component_count),
        .component0_frequency_hz(component0_frequency_hz),
        .component1_frequency_hz(component1_frequency_hz),
        .component2_frequency_hz(component2_frequency_hz),
        .component0_amplitude_uv(component0_amplitude_uv),
        .component1_amplitude_uv(component1_amplitude_uv),
        .component2_amplitude_uv(component2_amplitude_uv),
        .total_true_rms_uv(total_true_rms_uv)
    );

    // The post-FIR 20 MSPS stream preserves enough time resolution for an
    // accurate phase-dependent composite Vpp and for a qualitative waveform
    // containing exactly one or three fundamental periods.
    g_time_domain_display time_domain_display (
        .clk(clk_200), .rst_n(time_display_rst_n),
        .sample_valid(debug_fir_output_valid),
        .sample_data(debug_fir_output_data),
        .measurement_valid(measurement_valid),
        .fundamental_frequency_hz(component0_frequency_hz),
        .active_gain_q16(calibration_gain_q16),
        .render_request(waveform_render_request),
        .render_three_cycles(uart_three_cycle_mode),
        .display_read_addr(display_read_addr),
        .display_read_data(waveform_display_data),
        .display_ready(waveform_display_ready),
        .render_busy(waveform_render_busy),
        .render_done(waveform_render_done),
        .request_overrun(waveform_request_overrun),
        .total_vpp_valid(total_vpp_valid),
        .total_vpp_code(total_vpp_code),
        .total_vpp_uv(total_vpp_uv)
    );

    g_spectrum_display spectrum_display (
        .clk(clk_200), .rst_n(spectrum_display_rst_n),
        .spectrum_valid(spectrum_valid),
        .spectrum_bin(spectrum_bin), .spectrum_power(spectrum_power),
        .display_read_addr(display_read_addr),
        .display_read_data(spectrum_display_data),
        .display_ready(spectrum_display_ready),
        .frame_done(spectrum_display_done),
        .processing_busy(spectrum_display_busy),
        .capture_overrun(spectrum_display_overrun)
    );

    g_tjc_display_uart screen_interface (
        .clk(clk_200), .rst_n(screen_rst_n),
        .uart_rx(uart_rx), .uart_tx(uart_tx),
        .send_button_n(send_button_n),
        .measurement_valid(total_vpp_valid),
        .component_count(measurement_component_count),
        .total_vpp_uv(total_vpp_uv),
        .total_true_rms_uv(total_true_rms_uv),
        .component0_frequency_hz(component0_frequency_hz),
        .component1_frequency_hz(component1_frequency_hz),
        .component2_frequency_hz(component2_frequency_hz),
        .component0_amplitude_uv(component0_amplitude_uv),
        .component1_amplitude_uv(component1_amplitude_uv),
        .component2_amplitude_uv(component2_amplitude_uv),
        .waveform_display_ready(waveform_display_ready),
        .waveform_render_busy(waveform_render_busy),
        .waveform_render_done(waveform_render_done),
        .waveform_display_data(waveform_display_data),
        .spectrum_display_ready(spectrum_display_ready),
        .spectrum_display_data(spectrum_display_data),
        .display_read_addr(display_read_addr),
        .waveform_render_request(waveform_render_request),
        .three_cycle_mode(uart_three_cycle_mode),
        .spectrum_mode(uart_spectrum_mode),
        .calibrate_start(calibrate_start_uart),
        .calibration_reference_vpp_uv(calibration_reference_vpp_uv),
        .rx_calibrate_command(uart_rx_calibrate_command),
        .rx_framing_error_sticky(uart_rx_framing_error_sticky),
        .send_button_pressed(uart_send_button_pressed),
        .tx_busy(uart_tx_busy),
        .transfer_busy(uart_transfer_busy),
        .transfer_done(uart_transfer_done),
        .transparent_timeout_sticky(uart_transparent_timeout),
        .request_overrun(uart_request_overrun)
    );

endmodule
