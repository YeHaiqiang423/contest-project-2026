`timescale 1ns/1ps

module sat_gain #(
    parameter int WIDTH = 16,
    parameter int GAIN  = 3
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         in_valid,
    input  logic signed [WIDTH-1:0]      in_data,
    output logic                         out_valid,
    output logic signed [WIDTH-1:0]      out_data
);

    localparam int PRODUCT_WIDTH = 2 * WIDTH;
    localparam logic signed [PRODUCT_WIDTH-1:0] MAX_VALUE = (1 <<< (WIDTH - 1)) - 1;
    localparam logic signed [PRODUCT_WIDTH-1:0] MIN_VALUE = -(1 <<< (WIDTH - 1));

    logic signed [PRODUCT_WIDTH-1:0] product;
    logic signed [WIDTH-1:0] saturated;

    always_comb begin
        product = in_data * GAIN;
        if (product > MAX_VALUE)
            saturated = {1'b0, {(WIDTH - 1){1'b1}}};
        else if (product < MIN_VALUE)
            saturated = {1'b1, {(WIDTH - 1){1'b0}}};
        else
            saturated = product[WIDTH-1:0];
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_data  <= '0;
        end else begin
            out_valid <= in_valid;
            if (in_valid)
                out_data <= saturated;
        end
    end

endmodule
