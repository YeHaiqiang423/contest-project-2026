`timescale 1ns/1ps

// Mid-bit sampled 8-N-1 UART receiver. The two input registers are the CDC
// synchronizer for the asynchronous screen TX signal.
module g_uart_rx #(
    parameter integer CLK_HZ = 200000000,
    parameter integer BAUD = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid,
    output reg        framing_error
);

    localparam integer CLKS_PER_BIT = (CLK_HZ+(BAUD/2))/BAUD;
    localparam integer HALF_BIT = CLKS_PER_BIT/2;
    localparam integer COUNTER_WIDTH = 16;

    (* ASYNC_REG = "TRUE" *) reg [1:0] rx_sync;
    reg [COUNTER_WIDTH-1:0] bit_counter;
    reg [3:0] bit_index;
    reg [7:0] shift_register;
    reg receiving;

    initial begin
        if (CLKS_PER_BIT < 4)
            $error("UART CLKS_PER_BIT must be at least four");
        if (CLKS_PER_BIT > 65535)
            $error("UART CLKS_PER_BIT exceeds counter width");
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_sync <= 2'b11;
            bit_counter <= {COUNTER_WIDTH{1'b0}};
            bit_index <= 4'd0;
            shift_register <= 8'd0;
            data <= 8'd0;
            valid <= 1'b0;
            framing_error <= 1'b0;
            receiving <= 1'b0;
        end else begin
            rx_sync <= {rx_sync[0], rx};
            valid <= 1'b0;
            framing_error <= 1'b0;

            if (!receiving) begin
                if (!rx_sync[1]) begin
                    receiving <= 1'b1;
                    bit_counter <= HALF_BIT-1;
                    bit_index <= 4'd0;
                end
            end else if (bit_counter != 0) begin
                bit_counter <= bit_counter-1'b1;
            end else if (bit_index == 0) begin
                // Re-check the start bit at its centre to reject glitches.
                if (rx_sync[1]) begin
                    receiving <= 1'b0;
                end else begin
                    bit_counter <= CLKS_PER_BIT-1;
                    bit_index <= 4'd1;
                end
            end else if (bit_index <= 8) begin
                shift_register[bit_index-1] <= rx_sync[1];
                bit_counter <= CLKS_PER_BIT-1;
                bit_index <= bit_index+1'b1;
            end else begin
                receiving <= 1'b0;
                data <= shift_register;
                if (rx_sync[1])
                    valid <= 1'b1;
                else
                    framing_error <= 1'b1;
            end
        end
    end

endmodule

