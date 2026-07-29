`timescale 1ns/1ps

// Refine one Hann-windowed spectral peak from its left/center/right powers.
//
// Frequency offset:
//   delta = 2*(|X[k+1]|-|X[k-1]|) /
//           (|X[k-1]|+2*|X[k]|+|X[k+1]|)
// This Hann-specific three-bin estimator returns delta in signed Q1.15.
//
// Amplitude correction:
//   correction ~= 1 + 0.64744225*delta^2 + 0.25902453*delta^4
// The polynomial removes the Hann scalloping loss before the existing coherent
// gain/block-exponent scaler. Its fitted worst-case error over +/-0.5 bin is
// below 0.03 percent for the 4096-point symmetric Hann used by this project.
module g_hann_peak_refiner (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire [32:0]        left_power,
    input  wire [32:0]        center_power,
    input  wire [32:0]        right_power,
    input  wire [4:0]         block_exponent,
    output reg                busy,
    output reg                valid,
    output reg signed [15:0]  bin_offset_q15,
    output reg  [15:0]        amplitude_code
);

    localparam [16:0] COEFF_A_Q16 = 17'd42431;
    localparam [16:0] COEFF_B_Q16 = 17'd16975;

    reg [3:0] state;
    reg sqrt_start;
    reg [32:0] sqrt_input;
    reg [16:0] left_magnitude;
    reg [16:0] center_magnitude;
    reg offset_negative;

    reg divider_start;
    reg [17:0] divider_numerator;
    reg [18:0] divider_denominator;

    reg [15:0] delta2_q15;
    reg [15:0] delta4_q15;
    reg [17:0] term_a_q16;
    reg [17:0] term_b_q16;
    reg [17:0] correction_partial_q16;
    reg [17:0] correction_q16;
    reg [34:0] corrected_product;

    reg amplitude_start;
    reg [16:0] amplitude_magnitude;
    reg [4:0] exponent_latched;

    wire sqrt_busy;
    wire sqrt_valid;
    wire [16:0] sqrt_root;
    wire divider_busy;
    wire divider_valid;
    wire [15:0] divider_quotient_q15;
    wire amplitude_busy;
    wire amplitude_valid;
    wire [15:0] scaled_amplitude;

    wire [31:0] delta_square_product;
    wire [31:0] delta4_product;
    wire [32:0] term_a_product;
    wire [32:0] term_b_product;
    wire [18:0] corrected_rounded;

    assign delta_square_product = divider_quotient_q15*divider_quotient_q15;
    assign delta4_product = delta2_q15*delta2_q15;
    assign term_a_product = delta2_q15*COEFF_A_Q16;
    assign term_b_product = delta4_q15*COEFF_B_Q16;
    assign corrected_rounded = (corrected_product+35'd32768) >> 16;

    g_integer_sqrt peak_sqrt (
        .clk(clk), .rst_n(rst_n), .start(sqrt_start),
        .radicand(sqrt_input), .busy(sqrt_busy),
        .valid(sqrt_valid), .root(sqrt_root)
    );

    g_fractional_divider offset_divider (
        .clk(clk), .rst_n(rst_n), .start(divider_start),
        .numerator(divider_numerator),
        .denominator(divider_denominator), .busy(divider_busy),
        .valid(divider_valid), .quotient_q15(divider_quotient_q15)
    );

    g_hann_amplitude_scaler amplitude_scaler (
        .clk(clk), .rst_n(rst_n), .start(amplitude_start),
        .magnitude(amplitude_magnitude),
        .block_exponent(exponent_latched),
        .busy(amplitude_busy), .valid(amplitude_valid),
        .amplitude_code(scaled_amplitude)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= 4'd0;
            busy <= 1'b0;
            valid <= 1'b0;
            bin_offset_q15 <= 16'sd0;
            amplitude_code <= 16'd0;
            sqrt_start <= 1'b0;
            sqrt_input <= 33'd0;
            left_magnitude <= 17'd0;
            center_magnitude <= 17'd0;
            offset_negative <= 1'b0;
            divider_start <= 1'b0;
            divider_numerator <= 18'd0;
            divider_denominator <= 19'd0;
            delta2_q15 <= 16'd0;
            delta4_q15 <= 16'd0;
            term_a_q16 <= 18'd0;
            term_b_q16 <= 18'd0;
            correction_partial_q16 <= 18'd65536;
            correction_q16 <= 18'd65536;
            corrected_product <= 35'd0;
            amplitude_start <= 1'b0;
            amplitude_magnitude <= 17'd0;
            exponent_latched <= 5'd0;
        end else begin
            valid <= 1'b0;
            sqrt_start <= 1'b0;
            divider_start <= 1'b0;
            amplitude_start <= 1'b0;

            if (start && !busy) begin
                busy <= 1'b1;
                exponent_latched <= block_exponent;
                sqrt_input <= left_power;
                sqrt_start <= 1'b1;
                state <= 4'd1;
            end else if (state == 4'd1 && sqrt_valid) begin
                left_magnitude <= sqrt_root;
                sqrt_input <= center_power;
                sqrt_start <= 1'b1;
                state <= 4'd2;
            end else if (state == 4'd2 && sqrt_valid) begin
                center_magnitude <= sqrt_root;
                sqrt_input <= right_power;
                sqrt_start <= 1'b1;
                state <= 4'd3;
            end else if (state == 4'd3 && sqrt_valid) begin
                offset_negative <= sqrt_root < left_magnitude;
                divider_numerator <= (sqrt_root >= left_magnitude) ?
                    ({1'b0, sqrt_root-left_magnitude} << 1) :
                    ({1'b0, left_magnitude-sqrt_root} << 1);
                divider_denominator <= {2'b00, left_magnitude}+
                    {1'b0, center_magnitude, 1'b0}+
                    {2'b00, sqrt_root};
                divider_start <= 1'b1;
                state <= 4'd4;
            end else if (state == 4'd4 && divider_valid) begin
                bin_offset_q15 <= offset_negative ?
                    -$signed(divider_quotient_q15) :
                    $signed(divider_quotient_q15);
                delta2_q15 <= (delta_square_product+32'd16384) >> 15;
                state <= 4'd5;
            end else if (state == 4'd5) begin
                delta4_q15 <= (delta4_product+32'd16384) >> 15;
                term_a_q16 <= (term_a_product+33'd16384) >> 15;
                state <= 4'd6;
            end else if (state == 4'd6) begin
                term_b_q16 <= (term_b_product+33'd16384) >> 15;
                state <= 4'd7;
            end else if (state == 4'd7) begin
                correction_partial_q16 <= 18'd65536+term_a_q16;
                state <= 4'd8;
            end else if (state == 4'd8) begin
                correction_q16 <= correction_partial_q16+term_b_q16;
                state <= 4'd9;
            end else if (state == 4'd9) begin
                corrected_product <= center_magnitude*correction_q16;
                state <= 4'd10;
            end else if (state == 4'd10) begin
                amplitude_magnitude <= (corrected_rounded > 19'd131071) ?
                    17'h1ffff : corrected_rounded[16:0];
                amplitude_start <= 1'b1;
                state <= 4'd11;
            end else if (state == 4'd11 && amplitude_valid) begin
                amplitude_code <= scaled_amplitude;
                busy <= 1'b0;
                valid <= 1'b1;
                state <= 4'd0;
            end
        end
    end

endmodule
