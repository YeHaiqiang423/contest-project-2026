`timescale 1ns/1ps

// Iterative unsigned divider used for a Q1.15 fractional result. The quotient
// is floor((numerator << 15)/denominator). It is intentionally sequential:
// peak refinement happens after each FFT frame and is not on the 200 MHz
// streaming datapath.
module g_fractional_divider (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [17:0] numerator,
    input  wire [18:0] denominator,
    output reg         busy,
    output reg         valid,
    output reg  [15:0] quotient_q15
);

    reg [18:0] denominator_latched;
    reg [32:0] dividend_shift;
    reg [19:0] remainder;
    reg [32:0] quotient_work;
    reg [5:0] iteration;

    wire [19:0] remainder_shifted;
    wire subtract_ok;
    wire [19:0] remainder_next;
    wire [32:0] quotient_next;

    assign remainder_shifted = {remainder[18:0], dividend_shift[32]};
    assign subtract_ok = remainder_shifted >= {1'b0, denominator_latched};
    assign remainder_next = subtract_ok ?
        remainder_shifted-{1'b0, denominator_latched} : remainder_shifted;
    assign quotient_next = {quotient_work[31:0], subtract_ok};

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            valid <= 1'b0;
            quotient_q15 <= 16'd0;
            denominator_latched <= 19'd0;
            dividend_shift <= 33'd0;
            remainder <= 20'd0;
            quotient_work <= 33'd0;
            iteration <= 6'd0;
        end else begin
            valid <= 1'b0;

            if (start && !busy) begin
                if (denominator == 19'd0) begin
                    quotient_q15 <= 16'd0;
                    valid <= 1'b1;
                end else begin
                    busy <= 1'b1;
                    denominator_latched <= denominator;
                    dividend_shift <= {numerator, 15'd0};
                    remainder <= 20'd0;
                    quotient_work <= 33'd0;
                    iteration <= 6'd0;
                end
            end else if (busy) begin
                remainder <= remainder_next;
                dividend_shift <= dividend_shift << 1;
                quotient_work <= quotient_next;
                iteration <= iteration+1'b1;
                if (iteration == 6'd32) begin
                    quotient_q15 <= (|quotient_next[32:16]) ?
                        16'hffff : quotient_next[15:0];
                    busy <= 1'b0;
                    valid <= 1'b1;
                end
            end
        end
    end

endmodule
