`timescale 1ns/1ps

// Recover an approximate pre-Hann sine peak amplitude from the magnitude of
// one block-floating FFT bin. Shifting one bit per clock avoids a variable
// barrel shifter on the 200 MHz path.
module g_hann_amplitude_scaler (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [16:0] magnitude,
    input  wire [4:0]  block_exponent,
    output reg         busy,
    output reg         valid,
    output reg  [15:0] amplitude_code
);

    reg [41:0] working_value;
    reg [5:0] shifts_remaining;
    reg shift_left;
    reg finish_pending;

    wire [41:0] shifted_left;
    wire [41:0] shifted_right_rounded;

    assign shifted_left = working_value << 1;
    assign shifted_right_rounded = (working_value+1'b1) >> 1;

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            valid <= 1'b0;
            amplitude_code <= 16'd0;
            working_value <= 42'd0;
            shifts_remaining <= 6'd0;
            shift_left <= 1'b0;
            finish_pending <= 1'b0;
        end else begin
            valid <= 1'b0;

            if (start && !busy) begin
                busy <= 1'b1;
                working_value <= {25'd0, magnitude};
                finish_pending <= 1'b0;
                if (block_exponent >= 5'd10) begin
                    shift_left <= 1'b1;
                    shifts_remaining <= block_exponent-5'd10;
                    if (block_exponent == 5'd10)
                        finish_pending <= 1'b1;
                end else begin
                    shift_left <= 1'b0;
                    shifts_remaining <= 5'd10-block_exponent;
                end
            end else if (busy && finish_pending) begin
                if (working_value > 42'd65535)
                    amplitude_code <= 16'hffff;
                else
                    amplitude_code <= working_value[15:0];
                busy <= 1'b0;
                valid <= 1'b1;
                finish_pending <= 1'b0;
            end else if (busy && shifts_remaining != 0) begin
                if (shift_left)
                    working_value <= shifted_left;
                else if (shifts_remaining == 1)
                    working_value <= shifted_right_rounded;
                else
                    working_value <= working_value >> 1;
                shifts_remaining <= shifts_remaining-1'b1;
                if (shifts_remaining == 1)
                    finish_pending <= 1'b1;
            end
        end
    end

endmodule
