`timescale 1ns/1ps

// Publish a measurement only after two consecutive calibrated FFT frames
// agree.  This rejects the one mixed frame that can be produced while the
// signal source is enabled, disabled or changing frequency, while adding only
// one 2.048 ms frame of latency to a two-second contest requirement.
module g_measurement_stabilizer #(
    parameter integer FREQUENCY_TOLERANCE_HZ = 1000,
    parameter integer AMPLITUDE_TOLERANCE_UV = 5000,
    parameter integer RMS_TOLERANCE_UV = 5000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        measurement_valid,
    input  wire [1:0]  component_count_in,
    input  wire [19:0] component0_frequency_hz_in,
    input  wire [19:0] component1_frequency_hz_in,
    input  wire [19:0] component2_frequency_hz_in,
    input  wire [23:0] component0_amplitude_uv_in,
    input  wire [23:0] component1_amplitude_uv_in,
    input  wire [23:0] component2_amplitude_uv_in,
    input  wire [23:0] total_true_rms_uv_in,

    output reg         stable_valid,
    output reg         stable_locked,
    output reg  [1:0]  component_count,
    output reg  [19:0] component0_frequency_hz,
    output reg  [19:0] component1_frequency_hz,
    output reg  [19:0] component2_frequency_hz,
    output reg  [23:0] component0_amplitude_uv,
    output reg  [23:0] component1_amplitude_uv,
    output reg  [23:0] component2_amplitude_uv,
    output reg  [23:0] total_true_rms_uv
);

    reg previous_valid;
    reg [1:0] previous_count;
    reg [19:0] previous_frequency0;
    reg [19:0] previous_frequency1;
    reg [19:0] previous_frequency2;
    reg [23:0] previous_amplitude0;
    reg [23:0] previous_amplitude1;
    reg [23:0] previous_amplitude2;
    reg [23:0] previous_rms;
    reg difference_pending;
    reg difference_count_match;
    reg [19:0] difference_frequency0;
    reg [19:0] difference_frequency1;
    reg [19:0] difference_frequency2;
    reg [23:0] difference_amplitude0;
    reg [23:0] difference_amplitude1;
    reg [23:0] difference_amplitude2;
    reg [23:0] difference_rms;
    reg compare_pending;
    reg compare_count_match;
    reg compare_frequency0_match;
    reg compare_frequency1_match;
    reg compare_frequency2_match;
    reg compare_amplitude0_match;
    reg compare_amplitude1_match;
    reg compare_amplitude2_match;
    reg compare_rms_match;
    reg [1:0] candidate_count;
    reg [19:0] candidate_frequency0;
    reg [19:0] candidate_frequency1;
    reg [19:0] candidate_frequency2;
    reg [23:0] candidate_amplitude0;
    reg [23:0] candidate_amplitude1;
    reg [23:0] candidate_amplitude2;
    reg [23:0] candidate_rms;

    function [19:0] absolute_difference20;
        input [19:0] left_value;
        input [19:0] right_value;
        begin
            absolute_difference20 = (left_value >= right_value) ?
                left_value-right_value : right_value-left_value;
        end
    endfunction

    function [23:0] absolute_difference24;
        input [23:0] left_value;
        input [23:0] right_value;
        begin
            absolute_difference24 = (left_value >= right_value) ?
                left_value-right_value : right_value-left_value;
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            previous_valid <= 1'b0;
            previous_count <= 2'd0;
            previous_frequency0 <= 20'd0;
            previous_frequency1 <= 20'd0;
            previous_frequency2 <= 20'd0;
            previous_amplitude0 <= 24'd0;
            previous_amplitude1 <= 24'd0;
            previous_amplitude2 <= 24'd0;
            previous_rms <= 24'd0;
            difference_pending <= 1'b0;
            difference_count_match <= 1'b0;
            difference_frequency0 <= 20'd0;
            difference_frequency1 <= 20'd0;
            difference_frequency2 <= 20'd0;
            difference_amplitude0 <= 24'd0;
            difference_amplitude1 <= 24'd0;
            difference_amplitude2 <= 24'd0;
            difference_rms <= 24'd0;
            compare_pending <= 1'b0;
            compare_count_match <= 1'b0;
            compare_frequency0_match <= 1'b0;
            compare_frequency1_match <= 1'b0;
            compare_frequency2_match <= 1'b0;
            compare_amplitude0_match <= 1'b0;
            compare_amplitude1_match <= 1'b0;
            compare_amplitude2_match <= 1'b0;
            compare_rms_match <= 1'b0;
            candidate_count <= 2'd0;
            candidate_frequency0 <= 20'd0;
            candidate_frequency1 <= 20'd0;
            candidate_frequency2 <= 20'd0;
            candidate_amplitude0 <= 24'd0;
            candidate_amplitude1 <= 24'd0;
            candidate_amplitude2 <= 24'd0;
            candidate_rms <= 24'd0;
            stable_valid <= 1'b0;
            stable_locked <= 1'b0;
            component_count <= 2'd0;
            component0_frequency_hz <= 20'd0;
            component1_frequency_hz <= 20'd0;
            component2_frequency_hz <= 20'd0;
            component0_amplitude_uv <= 24'd0;
            component1_amplitude_uv <= 24'd0;
            component2_amplitude_uv <= 24'd0;
            total_true_rms_uv <= 24'd0;
        end else begin
            stable_valid <= 1'b0;

            // Publish one cycle after the individual comparisons were
            // registered.  This prevents seven subtract/compare chains from
            // converging on every result register enable in one 5 ns cycle.
            if (compare_pending) begin
                compare_pending <= 1'b0;
                if (compare_count_match &&
                        compare_frequency0_match &&
                        compare_frequency1_match &&
                        compare_frequency2_match &&
                        compare_amplitude0_match &&
                        compare_amplitude1_match &&
                        compare_amplitude2_match &&
                        compare_rms_match) begin
                    stable_valid <= 1'b1;
                    stable_locked <= 1'b1;
                    component_count <= candidate_count;
                    component0_frequency_hz <= candidate_frequency0;
                    component1_frequency_hz <= candidate_frequency1;
                    component2_frequency_hz <= candidate_frequency2;
                    component0_amplitude_uv <= candidate_amplitude0;
                    component1_amplitude_uv <= candidate_amplitude1;
                    component2_amplitude_uv <= candidate_amplitude2;
                    total_true_rms_uv <= candidate_rms;
                end else begin
                    stable_locked <= 1'b0;
                end
            end

            // Compare the already-registered differences in a separate cycle.
            // The former absolute-difference-plus-threshold chain was the
            // final routed 200 MHz violation.
            if (difference_pending) begin
                difference_pending <= 1'b0;
                compare_pending <= 1'b1;
                compare_count_match <= difference_count_match;
                compare_frequency0_match <=
                    difference_frequency0 <= FREQUENCY_TOLERANCE_HZ;
                compare_frequency1_match <= (candidate_count < 2) ||
                    difference_frequency1 <= FREQUENCY_TOLERANCE_HZ;
                compare_frequency2_match <= (candidate_count < 3) ||
                    difference_frequency2 <= FREQUENCY_TOLERANCE_HZ;
                compare_amplitude0_match <=
                    difference_amplitude0 <= AMPLITUDE_TOLERANCE_UV;
                compare_amplitude1_match <= (candidate_count < 2) ||
                    difference_amplitude1 <= AMPLITUDE_TOLERANCE_UV;
                compare_amplitude2_match <= (candidate_count < 3) ||
                    difference_amplitude2 <= AMPLITUDE_TOLERANCE_UV;
                compare_rms_match <= difference_rms <= RMS_TOLERANCE_UV;
            end

            if (measurement_valid) begin
                difference_pending <= 1'b1;
                difference_count_match <= previous_valid &&
                    component_count_in != 0 &&
                    component_count_in == previous_count;
                difference_frequency0 <=
                    absolute_difference20(component0_frequency_hz_in,
                        previous_frequency0);
                difference_frequency1 <=
                    absolute_difference20(component1_frequency_hz_in,
                        previous_frequency1);
                difference_frequency2 <=
                    absolute_difference20(component2_frequency_hz_in,
                        previous_frequency2);
                difference_amplitude0 <=
                    absolute_difference24(component0_amplitude_uv_in,
                        previous_amplitude0);
                difference_amplitude1 <=
                    absolute_difference24(component1_amplitude_uv_in,
                        previous_amplitude1);
                difference_amplitude2 <=
                    absolute_difference24(component2_amplitude_uv_in,
                        previous_amplitude2);
                difference_rms <=
                    absolute_difference24(total_true_rms_uv_in, previous_rms);
                candidate_count <= component_count_in;
                candidate_frequency0 <= component0_frequency_hz_in;
                candidate_frequency1 <= component1_frequency_hz_in;
                candidate_frequency2 <= component2_frequency_hz_in;
                candidate_amplitude0 <= component0_amplitude_uv_in;
                candidate_amplitude1 <= component1_amplitude_uv_in;
                candidate_amplitude2 <= component2_amplitude_uv_in;
                candidate_rms <= total_true_rms_uv_in;

                previous_valid <= component_count_in != 0;
                previous_count <= component_count_in;
                previous_frequency0 <= component0_frequency_hz_in;
                previous_frequency1 <= component1_frequency_hz_in;
                previous_frequency2 <= component2_frequency_hz_in;
                previous_amplitude0 <= component0_amplitude_uv_in;
                previous_amplitude1 <= component1_amplitude_uv_in;
                previous_amplitude2 <= component2_amplitude_uv_in;
                previous_rms <= total_true_rms_uv_in;
            end
        end
    end

endmodule
