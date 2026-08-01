`timescale 1ns/1ps

// Full-cycle Q1.15 sine lookup table.  One phase address produces both sine
// and cosine; cosine is the same table read one quarter cycle later.  The two
// registered reads infer the two ports of a block ROM in Vivado.
module g_sine_cos_rom #(
    parameter integer DATA_WIDTH = 16,
    parameter integer ADDR_WIDTH = 12,
    parameter integer DEPTH = 4096,
    parameter COEFF_FILE = "matlab/vectors/g_sine_q15_4096.hex"
) (
    input  wire                         clk,
    input  wire                         read_enable,
    input  wire [ADDR_WIDTH-1:0]        phase_addr,
    output reg signed [DATA_WIDTH-1:0] sin_data,
    output reg signed [DATA_WIDTH-1:0] cos_data
);

    localparam integer QUARTER_CYCLE = DEPTH/4;

    (* rom_style = "block" *)
    reg signed [DATA_WIDTH-1:0] sine_rom [0:DEPTH-1];

    wire [ADDR_WIDTH-1:0] cosine_addr;

    // DEPTH is 4096, so ADDR_WIDTH truncation implements modulo-4096.
    assign cosine_addr = phase_addr+QUARTER_CYCLE;

    initial begin
        if (DEPTH != (1 << ADDR_WIDTH))
            $error("g_sine_cos_rom requires DEPTH == 2^ADDR_WIDTH");
        if ((DEPTH & 3) != 0)
            $error("g_sine_cos_rom DEPTH must be divisible by four");
        $readmemh(COEFF_FILE, sine_rom);
    end

    always @(posedge clk) begin
        if (read_enable) begin
            sin_data <= sine_rom[phase_addr];
            cos_data <= sine_rom[cosine_addr];
        end
    end

endmodule
