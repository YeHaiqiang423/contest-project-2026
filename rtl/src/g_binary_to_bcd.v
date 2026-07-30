`timescale 1ns/1ps

// Iterative double-dabble converter. The display path is intentionally
// multi-cycle because it updates far more slowly than the 200 MHz DSP chain.
module g_binary_to_bcd #(
    parameter integer BINARY_WIDTH = 25,
    parameter integer DIGITS = 8
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire [BINARY_WIDTH-1:0]      binary,
    output reg                          busy,
    output reg                          valid,
    output reg  [(DIGITS*4)-1:0]        bcd
);

    reg [BINARY_WIDTH-1:0] binary_shift;
    reg [(DIGITS*4)-1:0] bcd_work;
    reg [7:0] iteration;
    integer digit_index;
    reg [(DIGITS*4)-1:0] bcd_adjusted;

    always @* begin
        bcd_adjusted = bcd_work;
        for (digit_index = 0; digit_index < DIGITS;
                digit_index = digit_index+1) begin
            if (bcd_work[(digit_index*4)+:4] >= 5)
                bcd_adjusted[(digit_index*4)+:4] =
                    bcd_work[(digit_index*4)+:4]+4'd3;
        end
    end

    initial begin
        if (BINARY_WIDTH < 1 || BINARY_WIDTH > 255)
            $error("BINARY_WIDTH must be 1..255");
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            valid <= 1'b0;
            bcd <= {(DIGITS*4){1'b0}};
            binary_shift <= {BINARY_WIDTH{1'b0}};
            bcd_work <= {(DIGITS*4){1'b0}};
            iteration <= 8'd0;
        end else begin
            valid <= 1'b0;
            if (start && !busy) begin
                busy <= 1'b1;
                binary_shift <= binary;
                bcd_work <= {(DIGITS*4){1'b0}};
                iteration <= 8'd0;
            end else if (busy) begin
                bcd_work <= {
                    bcd_adjusted[(DIGITS*4)-2:0],
                    binary_shift[BINARY_WIDTH-1]
                };
                binary_shift <= binary_shift << 1;
                iteration <= iteration+1'b1;
                if (iteration == BINARY_WIDTH-1) begin
                    bcd <= {
                        bcd_adjusted[(DIGITS*4)-2:0],
                        binary_shift[BINARY_WIDTH-1]
                    };
                    busy <= 1'b0;
                    valid <= 1'b1;
                end
            end
        end
    end

endmodule

