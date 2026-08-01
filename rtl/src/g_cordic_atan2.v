`timescale 1ns/1ps

// Iterative vectoring CORDIC.  The result is atan2(y_in, x_in) represented as
// an unsigned full-turn Q16 value: 0 == 0 degrees, 16'h4000 == 90 degrees,
// 16'h8000 == 180 degrees and 16'hc000 == 270 degrees.
//
// The intended phase-estimator mapping is x_in=S and y_in=C, yielding the
// sine-series phase atan2(C,S).  Each CORDIC iteration is split into a shift
// cycle and an add/subtract cycle to keep a variable shifter and a 50-bit
// carry chain off the same 200 MHz combinational path.
module g_cordic_atan2 #(
    parameter integer INPUT_WIDTH = 48,
    parameter integer ITERATIONS = 18
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start,
    input  wire signed [INPUT_WIDTH-1:0] x_in,
    input  wire signed [INPUT_WIDTH-1:0] y_in,
    output reg                           busy,
    output reg                           done,
    output reg  [15:0]                   angle_q16
);

    localparam integer WORK_WIDTH = INPUT_WIDTH+2;
    localparam signed [32:0] HALF_TURN_Q32 = 33'sd2147483648;

    reg signed [WORK_WIDTH-1:0] x_work;
    reg signed [WORK_WIDTH-1:0] y_work;
    reg signed [WORK_WIDTH-1:0] x_shift;
    reg signed [WORK_WIDTH-1:0] y_shift;
    reg signed [32:0] angle_work_q32;
    reg [4:0] iteration;
    reg rotate_phase;
    reg classify_pending;
    reg finalize_pending;

    wire signed [WORK_WIDTH-1:0] x_extended;
    wire signed [WORK_WIDTH-1:0] y_extended;
    wire signed [32:0] atan_step_q32;
    wire signed [32:0] angle_add_next_q32;
    wire signed [32:0] angle_sub_next_q32;

    assign x_extended = {{2{x_in[INPUT_WIDTH-1]}}, x_in};
    assign y_extended = {{2{y_in[INPUT_WIDTH-1]}}, y_in};
    assign atan_step_q32 = atan_constant_q32(iteration);
    assign angle_add_next_q32 = angle_work_q32+atan_step_q32;
    assign angle_sub_next_q32 = angle_work_q32-atan_step_q32;

    function signed [32:0] atan_constant_q32;
        input [4:0] index;
        begin
            case (index)
                5'd0:  atan_constant_q32 = 33'sd536870912;
                5'd1:  atan_constant_q32 = 33'sd316933406;
                5'd2:  atan_constant_q32 = 33'sd167458907;
                5'd3:  atan_constant_q32 = 33'sd85004756;
                5'd4:  atan_constant_q32 = 33'sd42667331;
                5'd5:  atan_constant_q32 = 33'sd21354465;
                5'd6:  atan_constant_q32 = 33'sd10679838;
                5'd7:  atan_constant_q32 = 33'sd5340245;
                5'd8:  atan_constant_q32 = 33'sd2670163;
                5'd9:  atan_constant_q32 = 33'sd1335087;
                5'd10: atan_constant_q32 = 33'sd667544;
                5'd11: atan_constant_q32 = 33'sd333772;
                5'd12: atan_constant_q32 = 33'sd166886;
                5'd13: atan_constant_q32 = 33'sd83443;
                5'd14: atan_constant_q32 = 33'sd41722;
                5'd15: atan_constant_q32 = 33'sd20861;
                5'd16: atan_constant_q32 = 33'sd10430;
                5'd17: atan_constant_q32 = 33'sd5215;
                5'd18: atan_constant_q32 = 33'sd2608;
                5'd19: atan_constant_q32 = 33'sd1304;
                default: atan_constant_q32 = 33'sd0;
            endcase
        end
    endfunction

    function [15:0] angle_to_q16;
        input signed [32:0] signed_angle_q32;
        begin
            // The low 32 bits already are modulo one turn even for a negative
            // two's-complement angle.  Only bit 15 is needed to round Q32 to
            // Q16; the discarded carry intentionally wraps 360 degrees to 0.
            angle_to_q16 = signed_angle_q32[31:16]+
                {15'd0, signed_angle_q32[15]};
        end
    endfunction

    initial begin
        if (INPUT_WIDTH < 2)
            $error("g_cordic_atan2 INPUT_WIDTH must be at least two");
        if (ITERATIONS < 1 || ITERATIONS > 20)
            $error("g_cordic_atan2 ITERATIONS must be in the range 1..20");
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
            angle_q16 <= 16'd0;
            x_work <= {WORK_WIDTH{1'b0}};
            y_work <= {WORK_WIDTH{1'b0}};
            x_shift <= {WORK_WIDTH{1'b0}};
            y_shift <= {WORK_WIDTH{1'b0}};
            angle_work_q32 <= 33'sd0;
            iteration <= 5'd0;
            rotate_phase <= 1'b0;
            classify_pending <= 1'b0;
            finalize_pending <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                // Register the wide correlation inputs before zero/quadrant
                // classification.  This prevents the 48-bit input compare
                // from sharing a cycle with the output control path.
                x_work <= x_extended;
                y_work <= y_extended;
                busy <= 1'b1;
                classify_pending <= 1'b1;
                finalize_pending <= 1'b0;
            end else if (classify_pending) begin
                classify_pending <= 1'b0;
                iteration <= 5'd0;
                rotate_phase <= 1'b0;
                // Bring quadrants II/III into the right half-plane and seed
                // z with +/-180 degrees.  Axes follow this same iterative
                // path, avoiding a 50-bit zero comparator on an output-enable
                // path. atan2(0,0) is intentionally unspecified; the phase
                // estimator suppresses it using its correlation-valid flag.
                if (x_work[WORK_WIDTH-1]) begin
                    x_work <= -x_work;
                    y_work <= -y_work;
                    angle_work_q32 <= y_work[WORK_WIDTH-1] ?
                        -HALF_TURN_Q32 : HALF_TURN_Q32;
                end else begin
                    angle_work_q32 <= 33'sd0;
                end
            end else if (finalize_pending) begin
                // Isolate atan-table selection and the 33-bit CORDIC add from
                // the final Q32-to-Q16 rounding carry chain.
                angle_q16 <= angle_to_q16(angle_work_q32);
                finalize_pending <= 1'b0;
                busy <= 1'b0;
                done <= 1'b1;
            end else if (busy) begin
                if (!rotate_phase) begin
                    x_shift <= x_work >>> iteration;
                    y_shift <= y_work >>> iteration;
                    rotate_phase <= 1'b1;
                end else begin
                    rotate_phase <= 1'b0;
                    if (y_work >= 0) begin
                        x_work <= x_work+y_shift;
                        y_work <= y_work-x_shift;
                        angle_work_q32 <= angle_add_next_q32;
                    end else begin
                        x_work <= x_work-y_shift;
                        y_work <= y_work+x_shift;
                        angle_work_q32 <= angle_sub_next_q32;
                    end

                    if (iteration == ITERATIONS-1) begin
                        finalize_pending <= 1'b1;
                    end else begin
                        iteration <= iteration+1'b1;
                    end
                end
            end
        end
    end

endmodule
