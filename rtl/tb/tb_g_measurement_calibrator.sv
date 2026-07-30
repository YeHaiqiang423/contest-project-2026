`timescale 1ns/1ps

module tb_g_measurement_calibrator;
    localparam logic [23:0] GAIN_25_UV_Q16 = 24'd1638400;
    localparam logic [23:0] GAIN_20_UV_Q16 = 24'd1310720;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic spectrum_results_valid = 1'b0;
    logic [1:0] component_count_in = 2'd0;
    logic [19:0] peak0_frequency_hz = 20'd0;
    logic [19:0] peak1_frequency_hz = 20'd0;
    logic [19:0] peak2_frequency_hz = 20'd0;
    logic [15:0] peak0_amplitude_code = 16'd0;
    logic [15:0] peak1_amplitude_code = 16'd0;
    logic [15:0] peak2_amplitude_code = 16'd0;
    logic gain_write = 1'b0;
    logic [23:0] gain_write_q16 = 24'd0;
    logic calibrate_start = 1'b0;
    logic [23:0] calibration_reference_vpp_uv = 24'd0;

    wire [23:0] active_gain_q16;
    wire calibration_busy;
    wire calibration_done;
    wire calibration_error;
    wire measurement_valid;
    wire measurement_overrun;
    wire [1:0] component_count;
    wire [19:0] component0_frequency_hz;
    wire [19:0] component1_frequency_hz;
    wire [19:0] component2_frequency_hz;
    wire [23:0] component0_amplitude_uv;
    wire [23:0] component1_amplitude_uv;
    wire [23:0] component2_amplitude_uv;
    wire [23:0] component0_rms_uv;
    wire [23:0] component1_rms_uv;
    wire [23:0] component2_rms_uv;
    wire [23:0] total_true_rms_uv;

    integer errors = 0;
    integer measurement_count = 0;
    integer calibration_count = 0;

    g_measurement_calibrator #(
        .DEFAULT_GAIN_UV_PER_CODE_Q16(GAIN_25_UV_Q16),
        .CAL_AVERAGE_LOG2(4)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .spectrum_results_valid(spectrum_results_valid),
        .component_count_in(component_count_in),
        .peak0_frequency_hz(peak0_frequency_hz),
        .peak1_frequency_hz(peak1_frequency_hz),
        .peak2_frequency_hz(peak2_frequency_hz),
        .peak0_amplitude_code(peak0_amplitude_code),
        .peak1_amplitude_code(peak1_amplitude_code),
        .peak2_amplitude_code(peak2_amplitude_code),
        .gain_write(gain_write), .gain_write_q16(gain_write_q16),
        .calibrate_start(calibrate_start),
        .calibration_reference_vpp_uv(calibration_reference_vpp_uv),
        .active_gain_q16(active_gain_q16),
        .calibration_busy(calibration_busy),
        .calibration_done(calibration_done),
        .calibration_error(calibration_error),
        .measurement_valid(measurement_valid),
        .measurement_overrun(measurement_overrun),
        .component_count(component_count),
        .component0_frequency_hz(component0_frequency_hz),
        .component1_frequency_hz(component1_frequency_hz),
        .component2_frequency_hz(component2_frequency_hz),
        .component0_amplitude_uv(component0_amplitude_uv),
        .component1_amplitude_uv(component1_amplitude_uv),
        .component2_amplitude_uv(component2_amplitude_uv),
        .component0_rms_uv(component0_rms_uv),
        .component1_rms_uv(component1_rms_uv),
        .component2_rms_uv(component2_rms_uv),
        .total_true_rms_uv(total_true_rms_uv)
    );

    always #2.5 clk = ~clk;

    task check_close;
        input integer actual;
        input integer expected;
        input integer tolerance;
        input string label_text;
        begin
            if ((actual < expected-tolerance) ||
                    (actual > expected+tolerance)) begin
                errors = errors+1;
                $error("%s got %0d expected %0d +/- %0d",
                    label_text, actual, expected, tolerance);
            end
        end
    endtask

    task pulse_result;
        input [1:0] count;
        input [19:0] f0;
        input [15:0] a0;
        input [19:0] f1;
        input [15:0] a1;
        input [19:0] f2;
        input [15:0] a2;
        begin
            @(negedge clk);
            component_count_in = count;
            peak0_frequency_hz = f0;
            peak0_amplitude_code = a0;
            peak1_frequency_hz = f1;
            peak1_amplitude_code = a1;
            peak2_frequency_hz = f2;
            peak2_amplitude_code = a2;
            spectrum_results_valid = 1'b1;
            @(negedge clk);
            spectrum_results_valid = 1'b0;
        end
    endtask

    task wait_measurement;
        input integer previous_count;
        begin
            while (measurement_count == previous_count)
                @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (measurement_valid) begin
            measurement_count = measurement_count+1;
            if ($isunknown({component_count,
                    component0_frequency_hz, component1_frequency_hz,
                    component2_frequency_hz, component0_amplitude_uv,
                    component1_amplitude_uv, component2_amplitude_uv,
                    component0_rms_uv, component1_rms_uv,
                    component2_rms_uv, total_true_rms_uv})) begin
                errors = errors+1;
                $error("Measurement output contains X/Z");
            end
        end
        if (calibration_done)
            calibration_count = calibration_count+1;
    end

    initial begin
        integer before_measurement;
        integer i;

        repeat (10) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        if (active_gain_q16 != GAIN_25_UV_Q16) begin
            errors = errors+1;
            $error("Default gain mismatch");
        end

        // Virtual three-component input deliberately arrives in power order
        // 300/100/500 kHz. The UART-facing output must be frequency ordered.
        before_measurement = measurement_count;
        pulse_result(2'd3, 20'd300000, 16'd4000,
            20'd100000, 16'd3000, 20'd500000, 16'd1000);
        wait_measurement(before_measurement);
        if (component_count != 2'd3 ||
                component0_frequency_hz != 20'd100000 ||
                component1_frequency_hz != 20'd300000 ||
                component2_frequency_hz != 20'd500000) begin
            errors = errors+1;
            $error("Frequency-order output mismatch");
        end
        check_close(component0_amplitude_uv, 75000, 1,
            "component0 peak uV");
        check_close(component1_amplitude_uv, 100000, 1,
            "component1 peak uV");
        check_close(component2_amplitude_uv, 25000, 1,
            "component2 peak uV");
        check_close(component0_rms_uv, 53033, 1, "component0 rms uV");
        check_close(component1_rms_uv, 70711, 1, "component1 rms uV");
        check_close(component2_rms_uv, 17678, 1, "component2 rms uV");
        check_close(total_true_rms_uv, 90125, 25, "total true rms uV");

        // Virtual direct-write trigger models a coefficient restored by UART.
        @(negedge clk);
        gain_write_q16 = GAIN_20_UV_Q16;
        gain_write = 1'b1;
        @(negedge clk);
        gain_write = 1'b0;
        repeat (2) @(posedge clk);
        if (active_gain_q16 != GAIN_20_UV_Q16 || calibration_error) begin
            errors = errors+1;
            $error("Direct gain-write calibration failed");
        end

        // Zero is invalid and must preserve the last known-good gain.
        @(negedge clk);
        gain_write_q16 = 24'd0;
        gain_write = 1'b1;
        @(negedge clk);
        gain_write = 1'b0;
        repeat (2) @(posedge clk);
        if (active_gain_q16 != GAIN_20_UV_Q16 || !calibration_error) begin
            errors = errors+1;
            $error("Invalid zero gain did not preserve the active gain");
        end

        before_measurement = measurement_count;
        pulse_result(2'd1, 20'd200000, 16'd5000,
            20'd0, 16'd0, 20'd0, 16'd0);
        wait_measurement(before_measurement);
        check_close(component0_amplitude_uv, 100000, 1,
            "direct-write peak uV");
        check_close(component0_rms_uv, 70711, 1,
            "direct-write component rms uV");
        check_close(total_true_rms_uv, 70700, 25,
            "direct-write total rms uV");

        // Automatic field calibration: 200 mVpp reference, 4000-code peak,
        // averaged over 16 virtual spectrum frames -> 25 uV/code exactly.
        @(negedge clk);
        calibration_reference_vpp_uv = 24'd200000;
        calibrate_start = 1'b1;
        @(negedge clk);
        calibrate_start = 1'b0;
        for (i = 0; i < 16; i = i+1) begin
            pulse_result(2'd1, 20'd100000, 16'd4000,
                20'd0, 16'd0, 20'd0, 16'd0);
            // The registered three-stage frequency sort plus RMS square-root
            // finishes far before a real 4096-point spectrum frame. Keep the
            // virtual frames separated enough to model that real cadence.
            repeat (60) @(posedge clk);
        end
        wait (!calibration_busy);
        repeat (2) @(posedge clk);
        if (active_gain_q16 != GAIN_25_UV_Q16 || calibration_error) begin
            errors = errors+1;
            $error("Automatic 16-frame calibration failed: gain=%0d error=%0b",
                active_gain_q16, calibration_error);
        end

        before_measurement = measurement_count;
        pulse_result(2'd1, 20'd100000, 16'd4000,
            20'd0, 16'd0, 20'd0, 16'd0);
        wait_measurement(before_measurement);
        check_close(component0_amplitude_uv, 100000, 1,
            "automatic-calibration peak uV");
        check_close(component0_rms_uv, 70711, 1,
            "automatic-calibration rms uV");

        if (measurement_overrun) begin
            errors = errors+1;
            $error("Unexpected measurement overrun");
        end
        if (calibration_count < 2) begin
            errors = errors+1;
            $error("Calibration done pulses missing: %0d", calibration_count);
        end

        if (errors == 0)
            $display("PASS: virtual triggers verify gain write, 16-frame calibration, frequency ordering, component peak/RMS and total true RMS");
        else
            $fatal(1, "FAIL: %0d measurement calibration errors", errors);
        $finish;
    end

    initial begin
        repeat (10000) @(posedge clk);
        $fatal(1, "Timeout waiting for measurement calibration self-check");
    end

endmodule
