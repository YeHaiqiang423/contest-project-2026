`timescale 1ns/1ps

// Pure-digital integration boundary: captured ADS6149 code to windowed FFT input.
module g_processing_pipeline #(
    parameter integer ADC_OFFSET_BINARY = 0,
    parameter integer FRAME_DECIMATION = 10,
    parameter integer FRAME_LENGTH = 4096,
    parameter integer FRAME_ADDR_WIDTH = 12,
    parameter integer HANN_ADDR_WIDTH = 11,
    parameter FIR_COEFF_FILE = "matlab/vectors/g_lpf_q17_unique.hex",
    parameter HANN_COEFF_FILE = "matlab/vectors/g_hann_q15_unique.hex"
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               capture_enable,
    input  wire               adc_valid,
    input  wire [13:0]        adc_data,
    input  wire               fft_ready,
    output wire               fft_valid,
    output wire signed [15:0] fft_real,
    output wire signed [15:0] fft_imag,
    output wire               fft_last,
    output wire               frame_done,
    output wire [1:0]         bank_pending,
    output wire               adc_input_overrun,
    output wire               frame_overrun,
    output reg                scheduler_overrun,
    output wire               debug_adc_sample_valid,
    output wire signed [13:0] debug_adc_sample_data,
    output wire               debug_fir_output_valid,
    output wire signed [15:0] debug_fir_output_data,
    output wire               debug_frame_ready,
    output wire               debug_frame_bank,
    output wire               debug_fft_busy
);

    wire adc_sample_valid;
    wire signed [13:0] adc_sample_data;
    wire fir_output_valid;
    wire signed [15:0] fir_output_data;
    wire frame_ready;
    wire frame_bank;
    wire capture_stalled;
    wire frame_read_enable;
    wire frame_read_bank;
    wire [FRAME_ADDR_WIDTH-1:0] frame_read_addr;
    wire signed [15:0] frame_read_data;
    wire frame_release_valid;
    wire frame_release_bank;
    wire fft_busy;
    wire fft_start;

    assign fft_start = frame_ready && !fft_busy;
    assign frame_done = frame_release_valid;
    assign debug_adc_sample_valid = adc_sample_valid;
    assign debug_adc_sample_data = adc_sample_data;
    assign debug_fir_output_valid = fir_output_valid;
    assign debug_fir_output_data = fir_output_data;
    assign debug_frame_ready = frame_ready;
    assign debug_frame_bank = frame_bank;
    assign debug_fft_busy = fft_busy;

    adc_sample_frontend #(
        .ADC_WIDTH(14), .DECIMATION(10),
        .INPUT_OFFSET_BINARY(ADC_OFFSET_BINARY)
    ) adc_frontend (
        .clk_adc(clk), .rst_n(rst_n), .adc_valid(adc_valid),
        .adc_data(adc_data), .sample_valid(adc_sample_valid),
        .sample_data(adc_sample_data)
    );

    g_symmetric_fir #(
        .COEFF_FILE(FIR_COEFF_FILE)
    ) lowpass_fir (
        .clk(clk), .rst_n(rst_n), .sample_valid(adc_sample_valid),
        .sample_data(adc_sample_data), .output_valid(fir_output_valid),
        .output_data(fir_output_data), .input_overrun(adc_input_overrun)
    );

    g_frame_capture #(
        .DATA_WIDTH(16), .DECIMATION(FRAME_DECIMATION),
        .FRAME_LENGTH(FRAME_LENGTH), .ADDR_WIDTH(FRAME_ADDR_WIDTH)
    ) frame_capture (
        .clk(clk), .rst_n(rst_n), .capture_enable(capture_enable),
        .sample_valid(fir_output_valid), .sample_data(fir_output_data),
        .frame_ready(frame_ready), .frame_bank(frame_bank),
        .bank_pending(bank_pending), .capture_stalled(capture_stalled),
        .frame_overrun(frame_overrun), .read_enable(frame_read_enable),
        .read_bank(frame_read_bank), .read_addr(frame_read_addr),
        .read_data(frame_read_data), .release_valid(frame_release_valid),
        .release_bank(frame_release_bank)
    );

    g_fft_input_stream #(
        .DATA_WIDTH(16), .FRAME_LENGTH(FRAME_LENGTH),
        .ADDR_WIDTH(FRAME_ADDR_WIDTH), .COEFF_ADDR_WIDTH(HANN_ADDR_WIDTH),
        .COEFF_FILE(HANN_COEFF_FILE)
    ) fft_input (
        .clk(clk), .rst_n(rst_n), .start(fft_start),
        .start_bank(frame_bank), .busy(fft_busy),
        .frame_read_enable(frame_read_enable), .frame_read_bank(frame_read_bank),
        .frame_read_addr(frame_read_addr), .frame_read_data(frame_read_data),
        .fft_valid(fft_valid), .fft_ready(fft_ready),
        .fft_real(fft_real), .fft_imag(fft_imag), .fft_last(fft_last),
        .release_valid(frame_release_valid), .release_bank(frame_release_bank)
    );

    always @(posedge clk) begin
        if (!rst_n)
            scheduler_overrun <= 1'b0;
        else if (frame_ready && fft_busy)
            scheduler_overrun <= 1'b1;
    end

endmodule
