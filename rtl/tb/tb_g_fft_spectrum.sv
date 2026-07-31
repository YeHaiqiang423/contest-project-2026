`timescale 1ns/1ps

module tb_g_fft_spectrum;
    localparam int NFFT = 4096;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic input_valid = 1'b0;
    logic signed [15:0] input_real = '0;
    logic signed [15:0] input_imag = '0;
    logic input_last = 1'b0;
    wire input_ready;
    wire fft_output_valid;
    wire fft_output_ready;
    wire signed [15:0] fft_output_real;
    wire signed [15:0] fft_output_imag;
    wire [11:0] fft_output_bin;
    wire [4:0] fft_output_block_exponent;
    wire fft_output_last;
    wire fft_frame_started;
    wire fft_configured;
    wire [4:0] fft_error_sticky;
    wire spectrum_valid;
    wire [11:0] spectrum_bin;
    wire [32:0] spectrum_power;
    wire [4:0] spectrum_block_exponent;
    wire results_valid;
    wire [1:0] component_count;
    wire [11:0] fundamental_bin;
    wire [19:0] fundamental_frequency_hz;
    wire [11:0] peak0_bin;
    wire [11:0] peak1_bin;
    wire [11:0] peak2_bin;
    wire [19:0] peak0_frequency_hz;
    wire [19:0] peak1_frequency_hz;
    wire [19:0] peak2_frequency_hz;
    wire [32:0] peak0_power;
    wire [32:0] peak1_power;
    wire [32:0] peak2_power;
    wire [15:0] peak0_amplitude_code;
    wire [15:0] peak1_amplitude_code;
    wire [15:0] peak2_amplitude_code;
    wire [4:0] result_block_exponent;
    wire measurement_valid;
    wire measurement_overrun;
    wire [1:0] measurement_component_count;
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

    integer vector_file;
    integer scan_count;
    integer sample_value;
    integer input_count = 0;
    integer output_count = 0;
    integer spectrum_count = 0;
    integer result_count = 0;
    integer measurement_count = 0;
    integer errors = 0;
    integer output_frame_exponent = -1;
    string vector_path;

    g_fft_core_wrapper fft_wrapper (
        .clk(clk), .rst_n(rst_n),
        .input_valid(input_valid), .input_ready(input_ready),
        .input_real(input_real), .input_imag(input_imag),
        .input_last(input_last), .output_valid(fft_output_valid),
        .output_ready(fft_output_ready), .output_real(fft_output_real),
        .output_imag(fft_output_imag), .output_bin(fft_output_bin),
        .output_block_exponent(fft_output_block_exponent),
        .output_last(fft_output_last), .frame_started(fft_frame_started),
        .configured(fft_configured), .error_sticky(fft_error_sticky)
    );

    g_spectrum_analyzer analyzer (
        .clk(clk), .rst_n(rst_n), .fft_valid(fft_output_valid),
        .fft_ready(fft_output_ready), .fft_real(fft_output_real),
        .fft_imag(fft_output_imag), .fft_bin(fft_output_bin),
        .fft_block_exponent(fft_output_block_exponent),
        .fft_last(fft_output_last), .spectrum_valid(spectrum_valid),
        .spectrum_bin(spectrum_bin), .spectrum_power(spectrum_power),
        .spectrum_block_exponent(spectrum_block_exponent),
        .results_valid(results_valid), .component_count(component_count),
        .fundamental_bin(fundamental_bin),
        .fundamental_frequency_hz(fundamental_frequency_hz),
        .peak0_bin(peak0_bin), .peak1_bin(peak1_bin), .peak2_bin(peak2_bin),
        .peak0_frequency_hz(peak0_frequency_hz),
        .peak1_frequency_hz(peak1_frequency_hz),
        .peak2_frequency_hz(peak2_frequency_hz),
        .peak0_power(peak0_power), .peak1_power(peak1_power),
        .peak2_power(peak2_power),
        .peak0_amplitude_code(peak0_amplitude_code),
        .peak1_amplitude_code(peak1_amplitude_code),
        .peak2_amplitude_code(peak2_amplitude_code),
        .result_block_exponent(result_block_exponent)
    );

    g_measurement_calibrator #(
        // Exact 25 uV/code makes the end-to-end golden values transparent.
        .DEFAULT_GAIN_UV_PER_CODE_Q16(24'd1638400)
    ) calibrator (
        .clk(clk), .rst_n(rst_n),
        .spectrum_results_valid(results_valid),
        .component_count_in(component_count),
        .peak0_frequency_hz(peak0_frequency_hz),
        .peak1_frequency_hz(peak1_frequency_hz),
        .peak2_frequency_hz(peak2_frequency_hz),
        .peak0_amplitude_code(peak0_amplitude_code),
        .peak1_amplitude_code(peak1_amplitude_code),
        .peak2_amplitude_code(peak2_amplitude_code),
        .gain_write(1'b0), .gain_write_q16(24'd0),
        .calibrate_start(1'b0),
        .calibration_reference_vpp_uv(24'd0),
        .active_gain_q16(), .calibration_busy(),
        .calibration_done(), .calibration_error(),
        .measurement_valid(measurement_valid),
        .measurement_overrun(measurement_overrun),
        .component_count(measurement_component_count),
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
            if ((actual < expected-tolerance) || (actual > expected+tolerance)) begin
                errors = errors+1;
                $error("%s got %0d expected %0d +/- %0d", label_text,
                    actual, expected, tolerance);
            end
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (input_valid && input_ready)
            input_count = input_count+1;

        if (fft_output_valid && fft_output_ready) begin
            if ($isunknown({fft_output_real, fft_output_imag, fft_output_bin,
                    fft_output_block_exponent, fft_output_last})) begin
                errors = errors+1;
                $error("FFT output contains X/Z at output %0d", output_count);
            end
            if (fft_output_bin !== (output_count % NFFT)) begin
                errors = errors+1;
                $error("FFT bin got %0d expected %0d", fft_output_bin,
                    output_count % NFFT);
            end
            if (fft_output_last !== ((output_count % NFFT) == NFFT-1)) begin
                errors = errors+1;
                $error("FFT TLAST mismatch at output %0d", output_count);
            end
            if ((output_count % NFFT) == 0)
                output_frame_exponent = fft_output_block_exponent;
            else if (fft_output_block_exponent != output_frame_exponent) begin
                errors = errors+1;
                $error("Block exponent changed inside frame");
            end
            output_count = output_count+1;
        end

        if (spectrum_valid)
            spectrum_count = spectrum_count+1;

        if (results_valid) begin
            $display("RESULT frame=%0d count=%0d fundamental_bin=%0d frequency=%0d Hz exp=%0d peaks=%0d/%0d/%0d amplitudes=%0d/%0d/%0d",
                result_count, component_count, fundamental_bin,
                fundamental_frequency_hz, result_block_exponent,
                peak0_bin, peak1_bin, peak2_bin,
                peak0_amplitude_code, peak1_amplitude_code,
                peak2_amplitude_code);
            if (result_count == 0) begin
                if (component_count != 1 || fundamental_bin != 1024 ||
                        peak0_bin != 1024) begin
                    errors = errors+1;
                    $error("Single-tone peak result mismatch");
                end
                check_close(fundamental_frequency_hz, 500000, 1,
                    "single-tone frequency");
                check_close(peak0_frequency_hz, 500000, 1,
                    "single-tone component frequency");
                check_close(peak0_amplitude_code, 800, 20,
                    "single-tone amplitude");
            end else if (result_count == 1) begin
                if (component_count != 3 || fundamental_bin != 205 ||
                        peak0_bin != 205 || peak1_bin != 512 ||
                        peak2_bin != 922) begin
                    errors = errors+1;
                    $error("Three-tone peak result mismatch");
                end
                check_close(fundamental_frequency_hz, 100098, 1,
                    "three-tone fundamental frequency");
                check_close(peak0_frequency_hz, 100098, 1,
                    "three-tone peak0 frequency");
                check_close(peak1_frequency_hz, 250000, 1,
                    "three-tone peak1 frequency");
                check_close(peak2_frequency_hz, 450195, 1,
                    "three-tone peak2 frequency");
                check_close(peak0_amplitude_code, 1000, 25,
                    "three-tone peak0 amplitude");
                check_close(peak1_amplitude_code, 300, 20,
                    "three-tone peak1 amplitude");
                check_close(peak2_amplitude_code, 120, 15,
                    "three-tone peak2 amplitude");
            end else if (result_count == 2) begin
                if (component_count != 1 || fundamental_bin != 20 ||
                        peak0_bin != 20) begin
                    errors = errors+1;
                    $error("10 kHz lower-bound peak result mismatch");
                end
                check_close(fundamental_frequency_hz, 10000, 50,
                    "10 kHz refined frequency");
                check_close(peak0_frequency_hz, 10000, 50,
                    "10 kHz component frequency");
                check_close(peak0_amplitude_code, 700, 20,
                    "10 kHz corrected amplitude");
            end else if (result_count == 3) begin
                if (component_count != 1 || fundamental_bin != 27 ||
                        peak0_bin != 27) begin
                    errors = errors+1;
                    $error("13 kHz peak result mismatch");
                end
                check_close(fundamental_frequency_hz, 13000, 50,
                    "13 kHz refined frequency");
                check_close(peak0_frequency_hz, 13000, 50,
                    "13 kHz component frequency");
                check_close(peak0_amplitude_code, 650, 20,
                    "13 kHz corrected amplitude");
            end else if (result_count == 4) begin
                if (component_count != 1 || fundamental_bin != 614 ||
                        peak0_bin != 614) begin
                    errors = errors+1;
                    $error("300 kHz off-bin peak result mismatch");
                end
                check_close(fundamental_frequency_hz, 300000, 50,
                    "300 kHz refined frequency");
                check_close(peak0_frequency_hz, 300000, 50,
                    "300 kHz component frequency");
                check_close(peak0_amplitude_code, 900, 25,
                    "300 kHz corrected amplitude");
            end else if (result_count == 5) begin
                if (component_count != 1 || peak0_bin != 1024) begin
                    errors = errors+1;
                    $error("500 kHz quadrature-phase boundary mismatch");
                end
                check_close(peak0_frequency_hz, 500000, 1,
                    "500 kHz quadrature-phase frequency");
                check_close(peak0_amplitude_code, 800, 20,
                    "500 kHz quadrature-phase amplitude");
            end else if (result_count == 6) begin
                if (component_count != 1 || peak0_bin != 1024) begin
                    errors = errors+1;
                    $error("499.9 kHz upper-boundary result mismatch");
                end
                check_close(peak0_frequency_hz, 499900, 75,
                    "499.9 kHz refined frequency");
                check_close(peak0_amplitude_code, 800, 25,
                    "499.9 kHz corrected amplitude");
            end else if (result_count == 7) begin
                if (component_count != 1 || peak0_bin != 1023) begin
                    errors = errors+1;
                    $error("499.5 kHz upper-boundary result mismatch");
                end
                check_close(peak0_frequency_hz, 499500, 75,
                    "499.5 kHz refined frequency");
                check_close(peak0_amplitude_code, 800, 25,
                    "499.5 kHz corrected amplitude");
            end else if (result_count == 8 || result_count == 9) begin
                if (component_count != 3 || peak0_bin != 819 ||
                        peak1_bin != 410 || peak2_bin != 205) begin
                    errors = errors+1;
                    $error("Weak-fundamental phase sweep peak mismatch");
                end
                check_close(peak0_frequency_hz, 400000, 75,
                    "weak-fundamental 400 kHz frequency");
                check_close(peak1_frequency_hz, 200000, 75,
                    "weak-fundamental 200 kHz frequency");
                check_close(peak2_frequency_hz, 100000, 75,
                    "weak-fundamental 100 kHz frequency");
                check_close(peak0_amplitude_code, 500, 25,
                    "weak-fundamental 400 kHz amplitude");
                check_close(peak1_amplitude_code, 400, 25,
                    "weak-fundamental 200 kHz amplitude");
                check_close(peak2_amplitude_code, 100, 12,
                    "weak-fundamental 100 kHz amplitude");
            end else begin
                errors = errors+1;
                $error("Unexpected extra result frame");
            end
            result_count = result_count+1;
        end

        if (measurement_valid) begin
            if ($isunknown({measurement_component_count,
                    component0_frequency_hz, component1_frequency_hz,
                    component2_frequency_hz, component0_amplitude_uv,
                    component1_amplitude_uv, component2_amplitude_uv,
                    component0_rms_uv, component1_rms_uv,
                    component2_rms_uv, total_true_rms_uv})) begin
                errors = errors+1;
                $error("Calibrated measurement contains X/Z");
            end
            if (measurement_count == 0) begin
                if (measurement_component_count != 1 ||
                        component0_frequency_hz != 500000)
                    errors = errors+1;
                check_close(component0_amplitude_uv, 20000, 500,
                    "500 kHz calibrated peak");
                check_close(component0_rms_uv, 14142, 500,
                    "500 kHz component rms");
                check_close(total_true_rms_uv, 14125, 500,
                    "500 kHz total rms");
            end else if (measurement_count == 1) begin
                if (measurement_component_count != 3 ||
                        component0_frequency_hz != 100098 ||
                        component1_frequency_hz != 250000 ||
                        component2_frequency_hz != 450195) begin
                    errors = errors+1;
                    $error("Different-phase three-tone frequency order mismatch");
                end
                check_close(component0_amplitude_uv, 25000, 625,
                    "three-tone component0 peak");
                check_close(component1_amplitude_uv, 7500, 500,
                    "three-tone component1 peak");
                check_close(component2_amplitude_uv, 3000, 375,
                    "three-tone component2 peak");
                check_close(component0_rms_uv, 17678, 625,
                    "three-tone component0 rms");
                check_close(component1_rms_uv, 5303, 500,
                    "three-tone component1 rms");
                check_close(component2_rms_uv, 2121, 375,
                    "three-tone component2 rms");
                check_close(total_true_rms_uv, 18575, 750,
                    "different-phase three-tone total true rms");
            end else if (measurement_count == 2) begin
                check_close(component0_frequency_hz, 10000, 50,
                    "10 kHz calibrated frequency");
                check_close(component0_amplitude_uv, 17500, 500,
                    "10 kHz calibrated peak");
            end else if (measurement_count == 3) begin
                check_close(component0_frequency_hz, 13000, 50,
                    "13 kHz calibrated frequency");
                check_close(component0_amplitude_uv, 16250, 500,
                    "13 kHz calibrated peak");
            end else if (measurement_count == 4) begin
                check_close(component0_frequency_hz, 300000, 50,
                    "300 kHz calibrated frequency");
                check_close(component0_amplitude_uv, 22500, 625,
                    "300 kHz calibrated peak");
            end else if (measurement_count == 5) begin
                check_close(component0_frequency_hz, 500000, 1,
                    "500 kHz quadrature calibrated frequency");
                check_close(component0_amplitude_uv, 20000, 500,
                    "500 kHz quadrature calibrated peak");
            end else if (measurement_count == 6) begin
                check_close(component0_frequency_hz, 499900, 75,
                    "499.9 kHz calibrated frequency");
                check_close(component0_amplitude_uv, 20000, 625,
                    "499.9 kHz calibrated peak");
            end else if (measurement_count == 7) begin
                check_close(component0_frequency_hz, 499500, 75,
                    "499.5 kHz calibrated frequency");
                check_close(component0_amplitude_uv, 20000, 625,
                    "499.5 kHz calibrated peak");
            end else if (measurement_count == 8 ||
                    measurement_count == 9) begin
                if (measurement_component_count != 3 ||
                        component0_frequency_hz < 99925 ||
                        component0_frequency_hz > 100075 ||
                        component1_frequency_hz < 199925 ||
                        component1_frequency_hz > 200075 ||
                        component2_frequency_hz < 399925 ||
                        component2_frequency_hz > 400075) begin
                    errors = errors+1;
                    $error("Weak-fundamental calibrated frequency order mismatch");
                end
                check_close(component0_amplitude_uv, 2500, 300,
                    "weak-fundamental calibrated 100 kHz peak");
                check_close(component1_amplitude_uv, 10000, 625,
                    "weak-fundamental calibrated 200 kHz peak");
                check_close(component2_amplitude_uv, 12500, 625,
                    "weak-fundamental calibrated 400 kHz peak");
            end else begin
                errors = errors+1;
                $error("Unexpected calibrated measurement frame");
            end
            measurement_count = measurement_count+1;
        end
    end

    initial begin
        if (!$value$plusargs("VECTOR_FILE=%s", vector_path))
            vector_path = "matlab/vectors/g_fft_spectrum_input.txt";
        vector_file = $fopen(vector_path, "r");
        if (vector_file == 0)
            $fatal(1, "Cannot open FFT vector file %s", vector_path);

        repeat (10) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        while (!$feof(vector_file)) begin
            scan_count = $fscanf(vector_file, "%d\n", sample_value);
            if (scan_count == 1) begin
                while (!input_ready)
                    @(negedge clk);
                input_valid = 1'b1;
                input_real = sample_value;
                input_imag = 16'sd0;
                input_last = ((input_count % NFFT) == NFFT-1);
                @(negedge clk);
                // Exercise the board stream's permitted input gaps. In the
                // FFT Non-Realtime mode these pause processing without
                // corrupting the frame and assert only the input-halt event.
                if ((input_count != 0) && ((input_count % 17) == 0)) begin
                    input_valid = 1'b0;
                    input_last = 1'b0;
                    @(negedge clk);
                end
            end
        end
        input_valid = 1'b0;
        input_last = 1'b0;
        $fclose(vector_file);

        wait (result_count == 10 && measurement_count == 10);
        repeat (10) @(posedge clk);
        if (input_count != 10*NFFT || output_count != 10*NFFT ||
                spectrum_count != 10*NFFT) begin
            errors = errors+1;
            $error("Frame counts input=%0d output=%0d spectrum=%0d",
                input_count, output_count, spectrum_count);
        end
        if ((fft_error_sticky & 5'b10111) != 5'b00000) begin
            errors = errors+1;
            $error("FFT fatal protocol/status sticky errors %b",
                fft_error_sticky);
        end
        if (!fft_error_sticky[3]) begin
            errors = errors+1;
            $error("Expected Non-Realtime input-wait event was not observed");
        end
        if (measurement_overrun) begin
            errors = errors+1;
            $error("Calibrated measurement overrun");
        end
        if (errors == 0)
            $display("PASS: ten FFT frames verify 500 kHz boundary phases, weak-fundamental phase separation, refined frequency and calibrated amplitudes");
        else
            $fatal(1, "FAIL: %0d FFT/spectrum errors", errors);
        $finish;
    end

    initial begin : simulation_timeout
        repeat (1000000) @(posedge clk);
        $fatal(1, "Timeout waiting for FFT spectrum results");
    end

endmodule
