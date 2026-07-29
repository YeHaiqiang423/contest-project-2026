`timescale 1ns/1ps

// Streaming post-processor for a natural-order 4096-point real FFT.
// It searches 10 kHz..500 kHz, retains the three strongest local peaks and
// reports an approximate Hann-corrected peak amplitude in ADC codes.
module g_spectrum_analyzer #(
    // 10 kHz is bin 20.48. The nearest/largest bin can therefore be bin 20;
    // starting at 21 discards the real main-lobe peak at the lower boundary.
    parameter integer MIN_BIN = 20,
    parameter integer MAX_BIN = 1024,
    // Power threshold = strongest_power / 2^PEAK_POWER_SHIFT.
    // 11 corresponds to an amplitude ratio of about 2.21 percent.
    parameter integer PEAK_POWER_SHIFT = 11
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               fft_valid,
    output wire               fft_ready,
    input  wire signed [15:0] fft_real,
    input  wire signed [15:0] fft_imag,
    input  wire [11:0]        fft_bin,
    input  wire [4:0]         fft_block_exponent,
    input  wire               fft_last,

    output reg                spectrum_valid,
    output reg  [11:0]        spectrum_bin,
    output reg  [32:0]        spectrum_power,
    output reg  [4:0]         spectrum_block_exponent,

    output reg                results_valid,
    output reg  [1:0]         component_count,
    output reg  [11:0]        fundamental_bin,
    output reg  [19:0]        fundamental_frequency_hz,
    output reg  [11:0]        peak0_bin,
    output reg  [11:0]        peak1_bin,
    output reg  [11:0]        peak2_bin,
    output reg  [32:0]        peak0_power,
    output reg  [32:0]        peak1_power,
    output reg  [32:0]        peak2_power,
    output reg  [15:0]        peak0_amplitude_code,
    output reg  [15:0]        peak1_amplitude_code,
    output reg  [15:0]        peak2_amplitude_code,
    output reg  [4:0]         result_block_exponent
);

    reg square_valid;
    reg [31:0] real_square;
    reg [31:0] imag_square;
    reg [11:0] square_bin;
    reg [4:0] square_exponent;
    reg square_last;
    reg spectrum_last;

    reg previous2_valid;
    reg previous1_valid;
    reg [32:0] previous2_power;
    reg [32:0] previous1_power;
    reg [11:0] previous2_bin;
    reg [11:0] previous1_bin;

    reg [32:0] candidate0_power;
    reg [32:0] candidate1_power;
    reg [32:0] candidate2_power;
    reg [32:0] candidate0_left_power;
    reg [32:0] candidate1_left_power;
    reg [32:0] candidate2_left_power;
    reg [32:0] candidate0_right_power;
    reg [32:0] candidate1_right_power;
    reg [32:0] candidate2_right_power;
    reg [11:0] candidate0_bin;
    reg [11:0] candidate1_bin;
    reg [11:0] candidate2_bin;
    reg [4:0] frame_exponent;
    reg finalize_pending;

    reg [32:0] peak0_left_power;
    reg [32:0] peak1_left_power;
    reg [32:0] peak2_left_power;
    reg [32:0] peak0_right_power;
    reg [32:0] peak1_right_power;
    reg [32:0] peak2_right_power;
    reg [19:0] peak0_frequency_hz;
    reg [19:0] peak1_frequency_hz;
    reg [19:0] peak2_frequency_hz;
    reg [4:0] result_state;
    reg [1:0] refine_index;
    reg refine_start;
    reg signed [28:0] frequency_bin_q15;
    (* use_dsp = "yes" *) reg signed [43:0] frequency_product;
    reg qualified0_latched;
    reg qualified1_latched;
    reg qualified2_latched;
    reg [11:0] fundamental_pair_bin;
    wire refine_busy;
    wire refine_valid;
    wire signed [15:0] refined_bin_offset_q15;
    wire [15:0] refined_amplitude_code;
    wire [32:0] refine_left_power;
    wire [32:0] refine_center_power;
    wire [32:0] refine_right_power;

    wire local_peak;
    wire [32:0] threshold_power;
    wire candidate0_qualified;
    wire candidate1_qualified;
    wire candidate2_qualified;
    wire [11:0] fundamental_latched01;

    assign fft_ready = 1'b1;
    assign local_peak = previous2_valid && previous1_valid &&
        (previous1_bin >= MIN_BIN) && (previous1_bin <= MAX_BIN) &&
        (previous1_power >= previous2_power) &&
        (previous1_power > spectrum_power);
    assign threshold_power = candidate0_power >> PEAK_POWER_SHIFT;
    assign candidate0_qualified = candidate0_power != 33'd0;
    assign candidate1_qualified = candidate1_power != 33'd0 &&
        candidate1_power >= threshold_power;
    assign candidate2_qualified = candidate2_power != 33'd0 &&
        candidate2_power >= threshold_power;
    assign fundamental_latched01 = qualified1_latched &&
        (peak1_bin < peak0_bin) ? peak1_bin : peak0_bin;
    assign refine_left_power = (refine_index == 2'd0) ? peak0_left_power :
        ((refine_index == 2'd1) ? peak1_left_power : peak2_left_power);
    assign refine_center_power = (refine_index == 2'd0) ? peak0_power :
        ((refine_index == 2'd1) ? peak1_power : peak2_power);
    assign refine_right_power = (refine_index == 2'd0) ? peak0_right_power :
        ((refine_index == 2'd1) ? peak1_right_power : peak2_right_power);

    g_hann_peak_refiner peak_refiner (
        .clk(clk), .rst_n(rst_n), .start(refine_start),
        .left_power(refine_left_power),
        .center_power(refine_center_power),
        .right_power(refine_right_power),
        .block_exponent(result_block_exponent),
        .busy(refine_busy), .valid(refine_valid),
        .bin_offset_q15(refined_bin_offset_q15),
        .amplitude_code(refined_amplitude_code)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            square_valid <= 1'b0;
            real_square <= 32'd0;
            imag_square <= 32'd0;
            square_bin <= 12'd0;
            square_exponent <= 5'd0;
            square_last <= 1'b0;
            spectrum_valid <= 1'b0;
            spectrum_bin <= 12'd0;
            spectrum_power <= 33'd0;
            spectrum_block_exponent <= 5'd0;
            spectrum_last <= 1'b0;
        end else begin
            square_valid <= fft_valid;
            if (fft_valid) begin
                real_square <= fft_real*fft_real;
                imag_square <= fft_imag*fft_imag;
                square_bin <= fft_bin;
                square_exponent <= fft_block_exponent;
                square_last <= fft_last;
            end

            spectrum_valid <= square_valid;
            if (square_valid) begin
                spectrum_power <= {1'b0, real_square}+{1'b0, imag_square};
                spectrum_bin <= square_bin;
                spectrum_block_exponent <= square_exponent;
                spectrum_last <= square_last;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            previous2_valid <= 1'b0;
            previous1_valid <= 1'b0;
            previous2_power <= 33'd0;
            previous1_power <= 33'd0;
            previous2_bin <= 12'd0;
            previous1_bin <= 12'd0;
            candidate0_power <= 33'd0;
            candidate1_power <= 33'd0;
            candidate2_power <= 33'd0;
            candidate0_left_power <= 33'd0;
            candidate1_left_power <= 33'd0;
            candidate2_left_power <= 33'd0;
            candidate0_right_power <= 33'd0;
            candidate1_right_power <= 33'd0;
            candidate2_right_power <= 33'd0;
            candidate0_bin <= 12'd0;
            candidate1_bin <= 12'd0;
            candidate2_bin <= 12'd0;
            frame_exponent <= 5'd0;
            finalize_pending <= 1'b0;
        end else begin
            finalize_pending <= 1'b0;
            if (spectrum_valid) begin
                if (spectrum_bin == 12'd0) begin
                    previous2_valid <= 1'b0;
                    previous1_valid <= 1'b1;
                    previous1_power <= spectrum_power;
                    previous1_bin <= spectrum_bin;
                    candidate0_power <= 33'd0;
                    candidate1_power <= 33'd0;
                    candidate2_power <= 33'd0;
                    candidate0_left_power <= 33'd0;
                    candidate1_left_power <= 33'd0;
                    candidate2_left_power <= 33'd0;
                    candidate0_right_power <= 33'd0;
                    candidate1_right_power <= 33'd0;
                    candidate2_right_power <= 33'd0;
                    candidate0_bin <= 12'd0;
                    candidate1_bin <= 12'd0;
                    candidate2_bin <= 12'd0;
                    frame_exponent <= spectrum_block_exponent;
                end else begin
                    if (local_peak) begin
                        if (previous1_power > candidate0_power) begin
                            candidate2_power <= candidate1_power;
                            candidate2_bin <= candidate1_bin;
                            candidate2_left_power <= candidate1_left_power;
                            candidate2_right_power <= candidate1_right_power;
                            candidate1_power <= candidate0_power;
                            candidate1_bin <= candidate0_bin;
                            candidate1_left_power <= candidate0_left_power;
                            candidate1_right_power <= candidate0_right_power;
                            candidate0_power <= previous1_power;
                            candidate0_bin <= previous1_bin;
                            candidate0_left_power <= previous2_power;
                            candidate0_right_power <= spectrum_power;
                        end else if (previous1_power > candidate1_power) begin
                            candidate2_power <= candidate1_power;
                            candidate2_bin <= candidate1_bin;
                            candidate2_left_power <= candidate1_left_power;
                            candidate2_right_power <= candidate1_right_power;
                            candidate1_power <= previous1_power;
                            candidate1_bin <= previous1_bin;
                            candidate1_left_power <= previous2_power;
                            candidate1_right_power <= spectrum_power;
                        end else if (previous1_power > candidate2_power) begin
                            candidate2_power <= previous1_power;
                            candidate2_bin <= previous1_bin;
                            candidate2_left_power <= previous2_power;
                            candidate2_right_power <= spectrum_power;
                        end
                    end
                    previous2_valid <= previous1_valid;
                    previous2_power <= previous1_power;
                    previous2_bin <= previous1_bin;
                    previous1_valid <= 1'b1;
                    previous1_power <= spectrum_power;
                    previous1_bin <= spectrum_bin;
                end

                if (spectrum_last)
                    finalize_pending <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            results_valid <= 1'b0;
            component_count <= 2'd0;
            fundamental_bin <= 12'd0;
            fundamental_frequency_hz <= 20'd0;
            peak0_bin <= 12'd0;
            peak1_bin <= 12'd0;
            peak2_bin <= 12'd0;
            peak0_power <= 33'd0;
            peak1_power <= 33'd0;
            peak2_power <= 33'd0;
            peak0_amplitude_code <= 16'd0;
            peak1_amplitude_code <= 16'd0;
            peak2_amplitude_code <= 16'd0;
            result_block_exponent <= 5'd0;
            peak0_left_power <= 33'd0;
            peak1_left_power <= 33'd0;
            peak2_left_power <= 33'd0;
            peak0_right_power <= 33'd0;
            peak1_right_power <= 33'd0;
            peak2_right_power <= 33'd0;
            peak0_frequency_hz <= 20'd0;
            peak1_frequency_hz <= 20'd0;
            peak2_frequency_hz <= 20'd0;
            result_state <= 5'd0;
            refine_index <= 2'd0;
            refine_start <= 1'b0;
            frequency_bin_q15 <= 29'sd0;
            frequency_product <= 44'sd0;
            qualified0_latched <= 1'b0;
            qualified1_latched <= 1'b0;
            qualified2_latched <= 1'b0;
            fundamental_pair_bin <= 12'd0;
        end else begin
            results_valid <= 1'b0;
            refine_start <= 1'b0;

            if (finalize_pending && result_state == 5'd0) begin
                peak0_bin <= candidate0_bin;
                peak1_bin <= candidate1_bin;
                peak2_bin <= candidate2_bin;
                peak0_power <= candidate0_power;
                peak1_power <= candidate1_power;
                peak2_power <= candidate2_power;
                peak0_left_power <= candidate0_left_power;
                peak1_left_power <= candidate1_left_power;
                peak2_left_power <= candidate2_left_power;
                peak0_right_power <= candidate0_right_power;
                peak1_right_power <= candidate1_right_power;
                peak2_right_power <= candidate2_right_power;
                result_block_exponent <= frame_exponent;
                qualified0_latched <= candidate0_qualified;
                qualified1_latched <= candidate1_qualified;
                qualified2_latched <= candidate2_qualified;
                result_state <= 5'd1;
            end else if (result_state == 5'd1) begin
                component_count <= {1'b0, qualified0_latched}+
                    {1'b0, qualified1_latched}+
                    {1'b0, qualified2_latched};
                fundamental_pair_bin <= qualified0_latched ?
                    fundamental_latched01 : 12'd0;
                result_state <= 5'd2;
            end else if (result_state == 5'd2) begin
                fundamental_bin <= qualified0_latched ?
                    ((qualified2_latched &&
                    (peak2_bin < fundamental_pair_bin)) ?
                    peak2_bin : fundamental_pair_bin) : 12'd0;
                refine_index <= 2'd0;
                result_state <= 5'd3;
            end else if (result_state == 5'd3) begin
                refine_start <= 1'b1;
                result_state <= 5'd4;
            end else if (result_state == 5'd4 && refine_valid) begin
                peak0_amplitude_code <= refined_amplitude_code;
                frequency_bin_q15 <=
                    $signed({1'b0, peak0_bin, 15'd0})+
                    $signed(refined_bin_offset_q15);
                result_state <= 5'd5;
            end else if (result_state == 5'd5) begin
                frequency_product <= frequency_bin_q15*15'sd15625;
                result_state <= 5'd6;
            end else if (result_state == 5'd6) begin
                peak0_frequency_hz <=
                    (frequency_product+44'sd524288) >>> 20;
                refine_index <= 2'd1;
                result_state <= 5'd7;
            end else if (result_state == 5'd7) begin
                refine_start <= 1'b1;
                result_state <= 5'd8;
            end else if (result_state == 5'd8 && refine_valid) begin
                peak1_amplitude_code <= refined_amplitude_code;
                frequency_bin_q15 <=
                    $signed({1'b0, peak1_bin, 15'd0})+
                    $signed(refined_bin_offset_q15);
                result_state <= 5'd9;
            end else if (result_state == 5'd9) begin
                frequency_product <= frequency_bin_q15*15'sd15625;
                result_state <= 5'd10;
            end else if (result_state == 5'd10) begin
                peak1_frequency_hz <=
                    (frequency_product+44'sd524288) >>> 20;
                refine_index <= 2'd2;
                result_state <= 5'd11;
            end else if (result_state == 5'd11) begin
                refine_start <= 1'b1;
                result_state <= 5'd12;
            end else if (result_state == 5'd12 && refine_valid) begin
                peak2_amplitude_code <= refined_amplitude_code;
                frequency_bin_q15 <=
                    $signed({1'b0, peak2_bin, 15'd0})+
                    $signed(refined_bin_offset_q15);
                result_state <= 5'd13;
            end else if (result_state == 5'd13) begin
                frequency_product <= frequency_bin_q15*15'sd15625;
                result_state <= 5'd14;
            end else if (result_state == 5'd14) begin
                peak2_frequency_hz <=
                    (frequency_product+44'sd524288) >>> 20;
                result_state <= 5'd15;
            end else if (result_state == 5'd15) begin
                if (!qualified0_latched)
                    fundamental_frequency_hz <= 20'd0;
                else if (fundamental_bin == peak0_bin)
                    fundamental_frequency_hz <= peak0_frequency_hz;
                else if (fundamental_bin == peak1_bin)
                    fundamental_frequency_hz <= peak1_frequency_hz;
                else
                    fundamental_frequency_hz <= peak2_frequency_hz;
                results_valid <= 1'b1;
                result_state <= 5'd0;
            end
        end
    end

endmodule
