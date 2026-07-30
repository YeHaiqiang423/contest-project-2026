`timescale 1ns/1ps

// Byte-oriented 8-N-1 UART transmitter.
module g_uart_tx #(
    parameter integer CLK_HZ = 200000000,
    parameter integer BAUD = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] data,
    output wire       tx,
    output reg        busy,
    output reg        done
);

    localparam integer CLKS_PER_BIT = (CLK_HZ+(BAUD/2))/BAUD;
    localparam integer COUNTER_WIDTH = 16;

    reg [COUNTER_WIDTH-1:0] bit_counter;
    reg [3:0] bit_index;
    reg [9:0] shift_register;

    assign tx = busy ? shift_register[0] : 1'b1;

    initial begin
        if (CLKS_PER_BIT < 4)
            $error("UART CLKS_PER_BIT must be at least four");
        if (CLKS_PER_BIT > 65535)
            $error("UART CLKS_PER_BIT exceeds counter width");
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
            bit_counter <= {COUNTER_WIDTH{1'b0}};
            bit_index <= 4'd0;
            shift_register <= 10'h3ff;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                // LSB first: start, eight data bits, stop.
                shift_register <= {1'b1, data, 1'b0};
                bit_counter <= CLKS_PER_BIT-1;
                bit_index <= 4'd0;
                busy <= 1'b1;
            end else if (busy) begin
                if (bit_counter == 0) begin
                    bit_counter <= CLKS_PER_BIT-1;
                    shift_register <= {1'b1, shift_register[9:1]};
                    if (bit_index == 4'd9) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        bit_index <= bit_index+1'b1;
                    end
                end else begin
                    bit_counter <= bit_counter-1'b1;
                end
            end
        end
    end

endmodule

