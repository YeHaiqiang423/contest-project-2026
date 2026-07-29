`timescale 1ns/1ps

// Single-clock simple dual-port RAM template compatible with Vivado BRAM inference.
module g_frame_ram #(
    parameter integer DATA_WIDTH = 16,
    parameter integer ADDR_WIDTH = 12,
    parameter integer DEPTH = 4096
) (
    input  wire                         clk,
    input  wire                         write_enable,
    input  wire [ADDR_WIDTH-1:0]        write_addr,
    input  wire signed [DATA_WIDTH-1:0] write_data,
    input  wire                         read_enable,
    input  wire [ADDR_WIDTH-1:0]        read_addr,
    output reg signed [DATA_WIDTH-1:0] read_data
);

    (* ram_style = "block" *)
    reg signed [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    always @(posedge clk) begin
        if (write_enable)
            memory[write_addr] <= write_data;
        if (read_enable)
            read_data <= memory[read_addr];
    end

endmodule
