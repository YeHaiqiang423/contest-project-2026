`timescale 1ns/1ps

// Convert spectrum peak codes to UART-friendly physical quantities.
//
// - Frequencies are integer Hz.
// - Amplitudes are sine peak values in integer microvolts, matching the U_i
//   definition in the contest statement (not component Vpp).
// - RMS outputs are integer microvolts.
// - gain_q16 is unsigned Q16.16 in microvolts per ADC amplitude code.
//
// A direct gain_write supports restoring a coefficient from UART/nonvolatile
// storage. calibrate_start instead averages 16 subsequent single-tone frames
// and computes gain from a known reference Vpp without requiring a UART.
module g_measurement_calibrator #(
    parameter [23:0] DEFAULT_GAIN_UV_PER_CODE_Q16 = 24'd2070648,
    parameter integer CAL_AVERAGE_LOG2 = 4,
    parameter integer CALIBRATION_FREQUENCY_HZ = 100000,
    parameter integer CALIBRATION_FREQUENCY_TOLERANCE_HZ = 1000
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        spectrum_results_valid,
    input  wire [1:0]  component_count_in,
    input  wire [19:0] peak0_frequency_hz,
    input  wire [19:0] peak1_frequency_hz,
    input  wire [19:0] peak2_frequency_hz,
    input  wire [15:0] peak0_amplitude_code,
    input  wire [15:0] peak1_amplitude_code,
    input  wire [15:0] peak2_amplitude_code,

    input  wire        gain_write,
    input  wire [23:0] gain_write_q16,
    input  wire        calibrate_start,
    input  wire [23:0] calibration_reference_vpp_uv,

    output reg  [23:0] active_gain_q16,
    output reg         calibration_busy,
    output reg         calibration_done,
    output reg         calibration_error,

    output reg         measurement_valid,
    output reg         measurement_overrun,
    output reg  [1:0]  component_count,
    output reg  [19:0] component0_frequency_hz,
    output reg  [19:0] component1_frequency_hz,
    output reg  [19:0] component2_frequency_hz,
    output reg  [23:0] component0_amplitude_uv,
    output reg  [23:0] component1_amplitude_uv,
    output reg  [23:0] component2_amplitude_uv,
    output reg  [23:0] component0_rms_uv,
    output reg  [23:0] component1_rms_uv,
    output reg  [23:0] component2_rms_uv,
    output reg  [23:0] total_true_rms_uv
);

    localparam integer CAL_FRAME_COUNT = (1 << CAL_AVERAGE_LOG2);
    localparam [15:0] INV_SQRT2_Q16 = 16'd46341;

    reg [19:0] sort_frequency0;
    reg [19:0] sort_frequency1;
    reg [19:0] sort_frequency2;
    reg [15:0] sort_amplitude0;
    reg [15:0] sort_amplitude1;
    reg [15:0] sort_amplitude2;

    reg [3:0] measurement_state;
    reg [1:0] count_latched;
    reg [19:0] frequency0_latched;
    reg [19:0] frequency1_latched;
    reg [19:0] frequency2_latched;
    reg [23:0] amplitude0_latched;
    reg [23:0] amplitude1_latched;
    reg [23:0] amplitude2_latched;
    reg [23:0] rms0_latched;
    reg [23:0] rms1_latched;
    reg [23:0] rms2_latched;

    (* use_dsp = "yes" *) reg [39:0] amplitude_product0;
    (* use_dsp = "yes" *) reg [39:0] amplitude_product1;
    (* use_dsp = "yes" *) reg [39:0] amplitude_product2;
    (* use_dsp = "yes" *) reg [31:0] code_square0;
    (* use_dsp = "yes" *) reg [31:0] code_square1;
    (* use_dsp = "yes" *) reg [31:0] code_square2;
    (* use_dsp = "yes" *) reg [39:0] rms_product0;
    (* use_dsp = "yes" *) reg [39:0] rms_product1;
    (* use_dsp = "yes" *) reg [39:0] rms_product2;
    reg [32:0] square_sum01;
    reg [31:0] square2_latched;
    reg sqrt_start;
    reg [32:0] total_rms_radicand;
    (* use_dsp = "yes" *) reg [40:0] total_scale_product;

    wire sqrt_busy;
    wire sqrt_valid;
    wire [16:0] total_rms_code;

    reg [2:0] calibration_state;
    reg [CAL_AVERAGE_LOG2-1:0] calibration_frame_count;
    reg [20:0] calibration_code_sum;
    reg [15:0] calibration_average_code;
    reg [23:0] calibration_reference_latched;
    reg divider_start;
    wire divider_busy;
    wire divider_valid;
    wire divider_zero;
    wire [39:0] divider_quotient;
    wire [39:0] calibration_numerator;

    wire [23:0] amplitude0_rounded;
    wire [23:0] amplitude1_rounded;
    wire [23:0] amplitude2_rounded;
    wire [23:0] rms0_rounded;
    wire [23:0] rms1_rounded;
    wire [23:0] rms2_rounded;
    wire [23:0] total_rms_rounded;
    wire [20:0] calibration_sum_next;

    function [23:0] round_q16_saturate;
        input [55:0] value;
        reg [39:0] shifted;
        begin
            shifted = (value+56'd32768) >> 16;
            if (|shifted[39:24])
                round_q16_saturate = 24'hffffff;
            else
                round_q16_saturate = shifted[23:0];
        end
    endfunction

    assign amplitude0_rounded = round_q16_saturate({16'd0, amplitude_product0});
    assign amplitude1_rounded = round_q16_saturate({16'd0, amplitude_product1});
    assign amplitude2_rounded = round_q16_saturate({16'd0, amplitude_product2});
    assign rms0_rounded = round_q16_saturate({16'd0, rms_product0});
    assign rms1_rounded = round_q16_saturate({16'd0, rms_product1});
    assign rms2_rounded = round_q16_saturate({16'd0, rms_product2});
    assign total_rms_rounded = round_q16_saturate({15'd0, total_scale_product});
    assign calibration_sum_next = calibration_code_sum+
        {5'd0, peak0_amplitude_code};
    assign calibration_numerator = {
        1'b0, calibration_reference_latched, 15'd0
    };

    g_integer_sqrt total_rms_sqrt (
        .clk(clk), .rst_n(rst_n), .start(sqrt_start),
        .radicand(total_rms_radicand), .busy(sqrt_busy),
        .valid(sqrt_valid), .root(total_rms_code)
    );

    g_unsigned_divider #(
        .NUMERATOR_WIDTH(40), .DENOMINATOR_WIDTH(16)
    ) calibration_divider (
        .clk(clk), .rst_n(rst_n), .start(divider_start),
        .numerator(calibration_numerator),
        .denominator(calibration_average_code),
        .busy(divider_busy), .valid(divider_valid),
        .divide_by_zero(divider_zero), .quotient(divider_quotient)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            measurement_state <= 4'd0;
            measurement_valid <= 1'b0;
            measurement_overrun <= 1'b0;
            component_count <= 2'd0;
            component0_frequency_hz <= 20'd0;
            component1_frequency_hz <= 20'd0;
            component2_frequency_hz <= 20'd0;
            component0_amplitude_uv <= 24'd0;
            component1_amplitude_uv <= 24'd0;
            component2_amplitude_uv <= 24'd0;
            component0_rms_uv <= 24'd0;
            component1_rms_uv <= 24'd0;
            component2_rms_uv <= 24'd0;
            total_true_rms_uv <= 24'd0;
            count_latched <= 2'd0;
            frequency0_latched <= 20'd0;
            frequency1_latched <= 20'd0;
            frequency2_latched <= 20'd0;
            amplitude0_latched <= 24'd0;
            amplitude1_latched <= 24'd0;
            amplitude2_latched <= 24'd0;
            rms0_latched <= 24'd0;
            rms1_latched <= 24'd0;
            rms2_latched <= 24'd0;
            amplitude_product0 <= 40'd0;
            amplitude_product1 <= 40'd0;
            amplitude_product2 <= 40'd0;
            code_square0 <= 32'd0;
            code_square1 <= 32'd0;
            code_square2 <= 32'd0;
            rms_product0 <= 40'd0;
            rms_product1 <= 40'd0;
            rms_product2 <= 40'd0;
            square_sum01 <= 33'd0;
            square2_latched <= 32'd0;
            sqrt_start <= 1'b0;
            total_rms_radicand <= 33'd0;
            total_scale_product <= 41'd0;
            sort_frequency0 <= 20'd0;
            sort_frequency1 <= 20'd0;
            sort_frequency2 <= 20'd0;
            sort_amplitude0 <= 16'd0;
            sort_amplitude1 <= 16'd0;
            sort_amplitude2 <= 16'd0;
        end else begin
            measurement_valid <= 1'b0;
            sqrt_start <= 1'b0;

            if (spectrum_results_valid && measurement_state != 4'd0)
                measurement_overrun <= 1'b1;

            if (measurement_state == 4'd0 && spectrum_results_valid) begin
                count_latched <= component_count_in;
                // Invalidate unused power-ranked peaks, then sort in three
                // registered compare/swap stages. This keeps the analyzer to
                // calibrator path inside the 5 ns board clock requirement.
                sort_frequency0 <= (component_count_in >= 1) ?
                    peak0_frequency_hz : 20'hfffff;
                sort_amplitude0 <= (component_count_in >= 1) ?
                    peak0_amplitude_code : 16'd0;
                sort_frequency1 <= (component_count_in >= 2) ?
                    peak1_frequency_hz : 20'hfffff;
                sort_amplitude1 <= (component_count_in >= 2) ?
                    peak1_amplitude_code : 16'd0;
                sort_frequency2 <= (component_count_in >= 3) ?
                    peak2_frequency_hz : 20'hfffff;
                sort_amplitude2 <= (component_count_in >= 3) ?
                    peak2_amplitude_code : 16'd0;
                measurement_state <= 4'd1;
            end else if (measurement_state == 4'd1) begin
                if (sort_frequency0 > sort_frequency1) begin
                    sort_frequency0 <= sort_frequency1;
                    sort_frequency1 <= sort_frequency0;
                    sort_amplitude0 <= sort_amplitude1;
                    sort_amplitude1 <= sort_amplitude0;
                end
                measurement_state <= 4'd2;
            end else if (measurement_state == 4'd2) begin
                if (sort_frequency1 > sort_frequency2) begin
                    sort_frequency1 <= sort_frequency2;
                    sort_frequency2 <= sort_frequency1;
                    sort_amplitude1 <= sort_amplitude2;
                    sort_amplitude2 <= sort_amplitude1;
                end
                measurement_state <= 4'd3;
            end else if (measurement_state == 4'd3) begin
                if (sort_frequency0 > sort_frequency1) begin
                    sort_frequency0 <= sort_frequency1;
                    sort_frequency1 <= sort_frequency0;
                    sort_amplitude0 <= sort_amplitude1;
                    sort_amplitude1 <= sort_amplitude0;
                end
                measurement_state <= 4'd4;
            end else if (measurement_state == 4'd4) begin
                frequency0_latched <= (count_latched >= 1) ?
                    sort_frequency0 : 20'd0;
                frequency1_latched <= (count_latched >= 2) ?
                    sort_frequency1 : 20'd0;
                frequency2_latched <= (count_latched >= 3) ?
                    sort_frequency2 : 20'd0;
                amplitude_product0 <= sort_amplitude0*active_gain_q16;
                amplitude_product1 <= sort_amplitude1*active_gain_q16;
                amplitude_product2 <= sort_amplitude2*active_gain_q16;
                code_square0 <= sort_amplitude0*sort_amplitude0;
                code_square1 <= sort_amplitude1*sort_amplitude1;
                code_square2 <= sort_amplitude2*sort_amplitude2;
                measurement_state <= 4'd5;
            end else if (measurement_state == 4'd5) begin
                amplitude0_latched <= amplitude0_rounded;
                amplitude1_latched <= amplitude1_rounded;
                amplitude2_latched <= amplitude2_rounded;
                square_sum01 <= {1'b0, code_square0}+{1'b0, code_square1};
                square2_latched <= code_square2;
                measurement_state <= 4'd6;
            end else if (measurement_state == 4'd6) begin
                rms_product0 <= amplitude0_latched*INV_SQRT2_Q16;
                rms_product1 <= amplitude1_latched*INV_SQRT2_Q16;
                rms_product2 <= amplitude2_latched*INV_SQRT2_Q16;
                total_rms_radicand <=
                    ({1'b0, square_sum01}+{2'b00, square2_latched}+1'b1) >> 1;
                sqrt_start <= 1'b1;
                measurement_state <= 4'd7;
            end else if (measurement_state == 4'd7) begin
                rms0_latched <= rms0_rounded;
                rms1_latched <= rms1_rounded;
                rms2_latched <= rms2_rounded;
                measurement_state <= 4'd8;
            end else if (measurement_state == 4'd8 && sqrt_valid) begin
                total_scale_product <= total_rms_code*active_gain_q16;
                measurement_state <= 4'd9;
            end else if (measurement_state == 4'd9) begin
                component_count <= count_latched;
                component0_frequency_hz <= frequency0_latched;
                component1_frequency_hz <= frequency1_latched;
                component2_frequency_hz <= frequency2_latched;
                component0_amplitude_uv <= amplitude0_latched;
                component1_amplitude_uv <= amplitude1_latched;
                component2_amplitude_uv <= amplitude2_latched;
                component0_rms_uv <= rms0_latched;
                component1_rms_uv <= rms1_latched;
                component2_rms_uv <= rms2_latched;
                total_true_rms_uv <= total_rms_rounded;
                measurement_valid <= 1'b1;
                measurement_state <= 4'd0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            active_gain_q16 <= DEFAULT_GAIN_UV_PER_CODE_Q16;
            calibration_busy <= 1'b0;
            calibration_done <= 1'b0;
            calibration_error <= 1'b0;
            calibration_state <= 3'd0;
            calibration_frame_count <= {CAL_AVERAGE_LOG2{1'b0}};
            calibration_code_sum <= 21'd0;
            calibration_average_code <= 16'd0;
            calibration_reference_latched <= 24'd0;
            divider_start <= 1'b0;
        end else begin
            calibration_done <= 1'b0;
            divider_start <= 1'b0;

            if (gain_write) begin
                calibration_done <= 1'b1;
                if (gain_write_q16 == 24'd0) begin
                    // A malformed UART/NVM write must not destroy the last
                    // known-good coefficient.
                    calibration_error <= 1'b1;
                end else begin
                    active_gain_q16 <= gain_write_q16;
                    calibration_error <= 1'b0;
                end
            end

            if (calibrate_start && !calibration_busy) begin
                if (calibration_reference_vpp_uv == 24'd0) begin
                    calibration_done <= 1'b1;
                    calibration_error <= 1'b1;
                end else begin
                    calibration_busy <= 1'b1;
                    calibration_error <= 1'b0;
                    calibration_state <= 3'd1;
                    calibration_frame_count <= {CAL_AVERAGE_LOG2{1'b0}};
                    calibration_code_sum <= 21'd0;
                    calibration_reference_latched <=
                        calibration_reference_vpp_uv;
                end
            end else if (calibration_state == 3'd1 &&
                    spectrum_results_valid) begin
                if (component_count_in != 2'd1 ||
                        peak0_amplitude_code == 16'd0 ||
                        peak0_frequency_hz <
                            CALIBRATION_FREQUENCY_HZ-
                            CALIBRATION_FREQUENCY_TOLERANCE_HZ ||
                        peak0_frequency_hz >
                            CALIBRATION_FREQUENCY_HZ+
                            CALIBRATION_FREQUENCY_TOLERANCE_HZ) begin
                    calibration_busy <= 1'b0;
                    calibration_done <= 1'b1;
                    calibration_error <= 1'b1;
                    calibration_state <= 3'd0;
                end else if (calibration_frame_count == CAL_FRAME_COUNT-1) begin
                    calibration_average_code <=
                        (calibration_sum_next+
                        (1 << (CAL_AVERAGE_LOG2-1))) >> CAL_AVERAGE_LOG2;
                    calibration_code_sum <= calibration_sum_next;
                    calibration_state <= 3'd2;
                end else begin
                    calibration_code_sum <= calibration_sum_next;
                    calibration_frame_count <= calibration_frame_count+1'b1;
                end
            end else if (calibration_state == 3'd2) begin
                divider_start <= 1'b1;
                calibration_state <= 3'd3;
            end else if (calibration_state == 3'd3 && divider_valid) begin
                calibration_busy <= 1'b0;
                calibration_done <= 1'b1;
                calibration_state <= 3'd0;
                if (divider_zero || |divider_quotient[39:24]) begin
                    calibration_error <= 1'b1;
                end else begin
                    active_gain_q16 <= divider_quotient[23:0];
                    calibration_error <= 1'b0;
                end
            end
        end
    end

endmodule
