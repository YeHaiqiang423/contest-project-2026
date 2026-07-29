`timescale 1ns/1ps

// Initial board-validation top for Mizar Z7 + direct-plug ADS6149 module.
// The ADS6149 CLKOUT capture path intentionally follows the vendor reference
// design. It is isolated from the 200 MHz algorithm clock by an XPM async FIFO.
module g_board_ila_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [13:0] adc0_data,
    input  wire        adc0_clk_in,
    output wire        adc0_clk_out
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

    wire [15:0] ila_control;
    wire [7:0] ila_fifo_status;

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
        .rst_n(system_rst_n),
        .capture_enable(1'b1),
        .adc_valid(adc_stream_valid),
        .adc_data(fifo_dout),
        .fft_ready(1'b1),
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

    // ila_control bit definitions are documented in hardware/notes/ila_test_guide.md.
    assign ila_control[0] = mmcm_locked;
    assign ila_control[1] = system_rst_n;
    assign ila_control[2] = adc_stream_valid;
    assign ila_control[3] = debug_adc_sample_valid;
    assign ila_control[4] = debug_fir_output_valid;
    assign ila_control[5] = debug_frame_ready;
    assign ila_control[6] = debug_frame_bank;
    assign ila_control[8:7] = bank_pending;
    assign ila_control[9] = fft_valid;
    assign ila_control[10] = fifo_read_started;
    assign ila_control[11] = fft_last;
    assign ila_control[12] = frame_done;
    assign ila_control[13] = adc_input_overrun;
    assign ila_control[14] = frame_overrun;
    assign ila_control[15] = scheduler_overrun;

    assign ila_fifo_status[0] = fifo_empty;
    assign ila_fifo_status[1] = fifo_status_sync[0];
    assign ila_fifo_status[2] = fifo_status_sync[1];
    assign ila_fifo_status[3] = fifo_status_sync[2];
    assign ila_fifo_status[4] = fifo_underflow;
    assign ila_fifo_status[5] = fifo_status_sync[3];
    assign ila_fifo_status[6] = fifo_rd_rst_busy;
    assign ila_fifo_status[7] = fifo_status_sync[4];

    board_ila initial_validation_ila (
        .clk(clk_200),
        .probe0(fifo_dout),
        .probe1(debug_adc_sample_data),
        .probe2(debug_fir_output_data),
        .probe3(fft_real),
        .probe4(ila_control),
        .probe5(ila_fifo_status)
    );

endmodule
