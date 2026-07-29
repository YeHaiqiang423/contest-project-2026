`timescale 1ns/1ps

// Iterative unsigned square root. A 33-bit radicand produces a 17-bit root
// in 17 clocks and is used only after one FFT frame has been unloaded.
module g_integer_sqrt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [32:0] radicand,
    output reg         busy,
    output reg         valid,
    output reg  [16:0] root
);

    reg [19:0] remainder;
    reg [16:0] partial_root;
    reg [33:0] input_shift;
    reg [4:0] iteration;

    wire [19:0] shifted_remainder;
    wire [19:0] trial_value;
    wire trial_succeeds;
    wire [19:0] remainder_next;
    wire [16:0] root_next;

    // Two input bits are consumed per clock. The partial remainder datapath
    // is only 20 bits, avoiding a 34-bit compare/subtract critical path.
    assign shifted_remainder = {remainder[17:0], input_shift[33:32]};
    assign trial_value = {1'b0, partial_root, 2'b01};
    assign trial_succeeds = shifted_remainder >= trial_value;
    assign remainder_next = trial_succeeds ?
        shifted_remainder-trial_value : shifted_remainder;
    assign root_next = {partial_root[15:0], trial_succeeds};

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            valid <= 1'b0;
            root <= 17'd0;
            remainder <= 20'd0;
            partial_root <= 17'd0;
            input_shift <= 34'd0;
            iteration <= 5'd0;
        end else begin
            valid <= 1'b0;

            if (start && !busy) begin
                busy <= 1'b1;
                remainder <= 20'd0;
                partial_root <= 17'd0;
                input_shift <= {1'b0, radicand};
                iteration <= 5'd0;
            end else if (busy) begin
                remainder <= remainder_next;
                partial_root <= root_next;
                input_shift <= input_shift << 2;
                iteration <= iteration+1'b1;
                if (iteration == 5'd16) begin
                    root <= root_next;
                    busy <= 1'b0;
                    valid <= 1'b1;
                end
            end
        end
    end

endmodule
