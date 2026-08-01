`timescale 1ns/1ps

module tb_g_phase_estimator #(
    parameter SINE_FILE = "matlab/vectors/g_sine_q15_4096.hex"
);
    localparam integer FRAME_LENGTH = 4096;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic fft_valid = 1'b0;
    logic fft_ready = 1'b1;
    logic signed [15:0] fft_real = 16'sd0;
    logic fft_last = 1'b0;
    logic spectrum_results_valid = 1'b0;
    logic [1:0] component_count = 2'd0;
    logic [19:0] peak0_frequency_hz = 20'd0;
    logic [19:0] peak1_frequency_hz = 20'd0;
    logic [19:0] peak2_frequency_hz = 20'd0;

    wire phase_results_valid;
    wire harmonic1_phase_valid;
    wire harmonic2_phase_valid;
    wire [8:0] harmonic1_phase_deg;
    wire [8:0] harmonic2_phase_deg;
    wire busy;
    wire [2:0] error_sticky;

    integer input_file;
    integer config_file;
    integer expected_file;
    integer scan_count;
    integer sample_value;
    integer sample_index;
    integer frame_count = 0;
    integer publish_count = 0;
    integer errors = 0;
    integer case_id;
    integer repeat_index;
    integer configured_count;
    integer frequency0;
    integer frequency1;
    integer frequency2;
    integer expected_case_id;
    integer expected_repeat_index;
    integer expected_fundamental;
    integer expected_phase0 = 999;
    integer expected_phase1 = 999;
    integer publish_before;
    string input_path;
    string config_path;
    string expected_path;

    always #2.5 clk = ~clk;

    g_phase_estimator #(
        .SINE_FILE(SINE_FILE)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .fft_valid(fft_valid), .fft_ready(fft_ready),
        .fft_real(fft_real), .fft_last(fft_last),
        .spectrum_results_valid(spectrum_results_valid),
        .component_count(component_count),
        .peak0_frequency_hz(peak0_frequency_hz),
        .peak1_frequency_hz(peak1_frequency_hz),
        .peak2_frequency_hz(peak2_frequency_hz),
        .phase_results_valid(phase_results_valid),
        .harmonic1_phase_valid(harmonic1_phase_valid),
        .harmonic2_phase_valid(harmonic2_phase_valid),
        .harmonic1_phase_deg(harmonic1_phase_deg),
        .harmonic2_phase_deg(harmonic2_phase_deg),
        .busy(busy), .error_sticky(error_sticky)
    );

    function automatic integer circular_error;
        input integer actual_degree;
        input integer wanted_degree;
        integer difference;
        begin
            difference = actual_degree-wanted_degree;
            while (difference > 180)
                difference = difference-360;
            while (difference < -180)
                difference = difference+360;
            circular_error = (difference < 0) ? -difference : difference;
        end
    endfunction

    task automatic check_phase_output;
        input integer expected_degree;
        input actual_valid;
        input [8:0] actual_degree;
        input string label_text;
        begin
            if (expected_degree == 999) begin
                if (actual_valid) begin
                    errors = errors+1;
                    $error("case %0d repeat %0d %s should be invalid, got %0d",
                        case_id, repeat_index, label_text, actual_degree);
                end
            end else if (!actual_valid) begin
                errors = errors+1;
                $error("case %0d repeat %0d %s unexpectedly invalid",
                    case_id, repeat_index, label_text);
            end else if (circular_error(actual_degree, expected_degree) > 1) begin
                errors = errors+1;
                $error("case %0d repeat %0d %s got %0d expected %0d +/-1",
                    case_id, repeat_index, label_text, actual_degree,
                    expected_degree);
            end
        end
    endtask

    task automatic send_constant_frame(input integer constant_value);
        begin
            for (sample_index = 0; sample_index < FRAME_LENGTH;
                    sample_index = sample_index+1) begin
                @(negedge clk);
                fft_valid = 1'b1;
                fft_real = constant_value;
                fft_last = sample_index == FRAME_LENGTH-1;
            end
            @(negedge clk);
            fft_valid = 1'b0;
            fft_real = 16'sd0;
            fft_last = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (phase_results_valid) begin
            publish_count = publish_count+1;
            check_phase_output(expected_phase0, harmonic1_phase_valid,
                harmonic1_phase_deg, "x0");
            check_phase_output(expected_phase1, harmonic2_phase_valid,
                harmonic2_phase_deg, "x1");
            $display("PHASE case=%0d repeat=%0d x0=%s%0d x1=%s%0d",
                case_id, repeat_index,
                harmonic1_phase_valid ? "" : "invalid/",
                harmonic1_phase_deg,
                harmonic2_phase_valid ? "" : "invalid/",
                harmonic2_phase_deg);
        end
    end

    task automatic send_windowed_frame;
        begin
            for (sample_index = 0; sample_index < FRAME_LENGTH;
                    sample_index = sample_index+1) begin
                scan_count = $fscanf(input_file, "%d\n", sample_value);
                if (scan_count != 1)
                    $fatal(1, "Phase input ended in frame %0d sample %0d",
                        frame_count, sample_index);
                @(negedge clk);
                fft_valid = 1'b1;
                fft_real = sample_value;
                fft_last = sample_index == FRAME_LENGTH-1;
            end
            @(negedge clk);
            fft_valid = 1'b0;
            fft_real = 16'sd0;
            fft_last = 1'b0;
        end
    endtask

    task automatic issue_spectrum_result;
        begin
            // Deliberately present the same components in descending/mixed
            // order.  The DUT must keep each phase associated with frequency
            // while sorting into fundamental/x0/x1 display order.
            @(negedge clk);
            component_count = configured_count[1:0];
            if (configured_count == 3) begin
                peak0_frequency_hz = frequency2;
                peak1_frequency_hz = frequency0;
                peak2_frequency_hz = frequency1;
            end else if (configured_count == 2) begin
                peak0_frequency_hz = frequency1;
                peak1_frequency_hz = frequency0;
                peak2_frequency_hz = 20'd0;
            end else begin
                peak0_frequency_hz = frequency0;
                peak1_frequency_hz = 20'd0;
                peak2_frequency_hz = 20'd0;
            end
            spectrum_results_valid = 1'b1;
            @(negedge clk);
            spectrum_results_valid = 1'b0;
        end
    endtask

    initial begin
        if (!$value$plusargs("PHASE_INPUT=%s", input_path))
            input_path = "matlab/vectors/g_phase_input.txt";
        if (!$value$plusargs("PHASE_CONFIG=%s", config_path))
            config_path = "matlab/vectors/g_phase_config.txt";
        if (!$value$plusargs("PHASE_EXPECTED=%s", expected_path))
            expected_path = "matlab/vectors/g_phase_expected.txt";
        input_file = $fopen(input_path, "r");
        config_file = $fopen(config_path, "r");
        expected_file = $fopen(expected_path, "r");
        if ((input_file == 0) || (config_file == 0) ||
                (expected_file == 0))
            $fatal(1, "Cannot open phase-estimator vector files");

        repeat (10) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        while (!$feof(config_file)) begin
            scan_count = $fscanf(config_file, "%d %d %d %d %d %d\n",
                case_id, repeat_index, configured_count,
                frequency0, frequency1, frequency2);
            if (scan_count == 6) begin
                scan_count = $fscanf(expected_file, "%d %d %d %d %d\n",
                    expected_case_id, expected_repeat_index,
                    expected_fundamental, expected_phase0, expected_phase1);
                if ((scan_count != 5) || (case_id != expected_case_id) ||
                        (repeat_index != expected_repeat_index) ||
                        (expected_fundamental != 0))
                    $fatal(1, "Phase config/expected alignment failure");

                while (busy)
                    @(posedge clk);
                send_windowed_frame();
                repeat (4) @(posedge clk);
                publish_before = publish_count;
                issue_spectrum_result();
                wait (busy);
                wait (!busy);
                @(negedge clk);

                // Every second identical frame must have produced a stable
                // result.  A first repeat may also publish if it is equivalent
                // to the immediately preceding case (the shifted-wrap test).
                if ((repeat_index == 1) &&
                        (publish_count == publish_before)) begin
                    errors = errors+1;
                    $error("case %0d second frame did not publish", case_id);
                end
                frame_count = frame_count+1;
            end
        end

        $fclose(input_file);
        $fclose(config_file);
        $fclose(expected_file);

        // Invalid components must stabilize to 999 even if the rounded
        // non-harmonic orders change between frames.  Otherwise a disappeared
        // harmonic could leave an old valid phase visible indefinitely.
        case_id = 99;
        repeat_index = 0;
        expected_phase0 = 999;
        expected_phase1 = 999;
        configured_count = 3;
        frequency0 = 100000;
        frequency1 = 230000;
        frequency2 = 370000;
        send_constant_frame(0);
        issue_spectrum_result();
        wait (busy);
        wait (!busy);

        repeat_index = 1;
        frequency1 = 260000;
        frequency2 = 440000;
        send_constant_frame(0);
        publish_before = publish_count;
        issue_spectrum_result();
        wait (busy);
        wait (!busy);
        @(negedge clk);
        if (publish_count == publish_before) begin
            errors = errors+1;
            $error("Changing invalid harmonic orders did not publish 999/999");
        end

        if (error_sticky != 3'b000) begin
            errors = errors+1;
            $error("Unexpected diagnostics before overlap test: %b",
                error_sticky);
        end

        // Once a complete frame is waiting for its spectrum result, a newer
        // frame must be dropped without overwriting or discarding the older
        // sample RAM contents.
        send_constant_frame(0);
        send_constant_frame(123);
        if (error_sticky != 3'b100) begin
            errors = errors+1;
            $error("Protected-frame overlap diagnostic got %b expected 100",
                error_sticky);
        end
        configured_count = 1;
        frequency0 = 100000;
        frequency1 = 0;
        frequency2 = 0;
        issue_spectrum_result();
        wait (busy);
        wait (!busy);
        repeat (10) @(posedge clk);

        if (frame_count != 18) begin
            errors = errors+1;
            $error("Phase frame count got %0d expected 18", frame_count);
        end
        if (error_sticky != 3'b100) begin
            errors = errors+1;
            $error("Phase estimator sticky diagnostics got %b expected 100",
                error_sticky);
        end

        if (errors == 0)
            $display("PASS: 18 Hann-windowed vectors plus invalid-order and protected-frame overlap tests verify phase estimation to +/-1 degree");
        else
            $fatal(1, "FAIL: %0d phase-estimator errors", errors);
        $finish;
    end

    initial begin
        repeat (4000000) @(posedge clk);
        $fatal(1, "Timeout in phase-estimator self-check");
    end

endmodule
