`timescale 1ns/1ps

module g_hann_rom #(
    parameter integer COEFF_WIDTH = 16,
    parameter integer ADDR_WIDTH = 11,
    parameter integer DEPTH = 2048,
    parameter COEFF_FILE = "matlab/vectors/g_hann_q15_unique.hex"
) (
    input  wire                          clk,
    input  wire                          read_enable,
    input  wire [ADDR_WIDTH-1:0]         read_addr,
    output reg signed [COEFF_WIDTH-1:0] read_data
);

    (* rom_style = "block" *)
    reg signed [COEFF_WIDTH-1:0] memory [0:DEPTH-1];

    initial begin
        $readmemh(COEFF_FILE, memory);
    end

    always @(posedge clk) begin
        if (read_enable)
            read_data <= memory[read_addr];
    end

endmodule
