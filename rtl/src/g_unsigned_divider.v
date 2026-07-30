`timescale 1ns/1ps

// Multi-cycle restoring unsigned divider. One numerator bit is consumed per
// clock, keeping calibration division off the 200 MHz combinational path.
module g_unsigned_divider #(
    parameter integer NUMERATOR_WIDTH = 40,
    parameter integer DENOMINATOR_WIDTH = 16
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire [NUMERATOR_WIDTH-1:0]   numerator,
    input  wire [DENOMINATOR_WIDTH-1:0] denominator,
    output reg                          busy,
    output reg                          valid,
    output reg                          divide_by_zero,
    output reg  [NUMERATOR_WIDTH-1:0]   quotient
);

    reg [NUMERATOR_WIDTH-1:0] dividend;
    reg [NUMERATOR_WIDTH-1:0] quotient_work;
    reg [DENOMINATOR_WIDTH:0] remainder;
    reg [DENOMINATOR_WIDTH-1:0] denominator_latched;
    reg [7:0] iteration;

    wire [DENOMINATOR_WIDTH:0] shifted_remainder;
    wire trial_succeeds;
    wire [DENOMINATOR_WIDTH:0] remainder_next;
    wire [NUMERATOR_WIDTH-1:0] quotient_next;

    assign shifted_remainder = {
        remainder[DENOMINATOR_WIDTH-1:0],
        dividend[NUMERATOR_WIDTH-1]
    };
    assign trial_succeeds = shifted_remainder >=
        {1'b0, denominator_latched};
    assign remainder_next = trial_succeeds ?
        shifted_remainder-{1'b0, denominator_latched} : shifted_remainder;
    assign quotient_next = {
        quotient_work[NUMERATOR_WIDTH-2:0], trial_succeeds
    };

    initial begin
        if (NUMERATOR_WIDTH < 2)
            $error("NUMERATOR_WIDTH must be at least two");
        if (NUMERATOR_WIDTH > 255)
            $error("NUMERATOR_WIDTH must fit the iteration counter");
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            valid <= 1'b0;
            divide_by_zero <= 1'b0;
            quotient <= {NUMERATOR_WIDTH{1'b0}};
            dividend <= {NUMERATOR_WIDTH{1'b0}};
            quotient_work <= {NUMERATOR_WIDTH{1'b0}};
            remainder <= {(DENOMINATOR_WIDTH+1){1'b0}};
            denominator_latched <= {DENOMINATOR_WIDTH{1'b0}};
            iteration <= 8'd0;
        end else begin
            valid <= 1'b0;
            divide_by_zero <= 1'b0;

            if (start && !busy) begin
                if (denominator == {DENOMINATOR_WIDTH{1'b0}}) begin
                    quotient <= {NUMERATOR_WIDTH{1'b1}};
                    divide_by_zero <= 1'b1;
                    valid <= 1'b1;
                end else begin
                    busy <= 1'b1;
                    dividend <= numerator;
                    quotient_work <= {NUMERATOR_WIDTH{1'b0}};
                    remainder <= {(DENOMINATOR_WIDTH+1){1'b0}};
                    denominator_latched <= denominator;
                    iteration <= 8'd0;
                end
            end else if (busy) begin
                dividend <= dividend << 1;
                quotient_work <= quotient_next;
                remainder <= remainder_next;
                iteration <= iteration+1'b1;
                if (iteration == NUMERATOR_WIDTH-1) begin
                    quotient <= quotient_next;
                    busy <= 1'b0;
                    valid <= 1'b1;
                end
            end
        end
    end

endmodule
