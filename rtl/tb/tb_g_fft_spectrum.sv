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
    wire [32:0] peak0_power;
    wire [32:0] peak1_power;
    wire [32:0] peak2_power;
    wire [15:0] peak0_amplitude_code;
    wire [15:0] peak1_amplitude_code;
    wire [15:0] peak2_amplitude_code;
    wire [4:0] result_block_exponent;

    integer vector_file;
    integer scan_count;
    integer sample_value;
    integer input_count = 0;
    integer output_count = 0;
    integer spectrum_count = 0;
    integer result_count = 0;
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
        .peak0_power(peak0_power), .peak1_power(peak1_power),
        .peak2_power(peak2_power),
        .peak0_amplitude_code(peak0_amplitude_code),
        .peak1_amplitude_code(peak1_amplitude_code),
        .peak2_amplitude_code(peak2_amplitude_code),
        .result_block_exponent(result_block_exponent)
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
                check_close(peak0_amplitude_code, 900, 25,
                    "300 kHz corrected amplitude");
            end else begin
                errors = errors+1;
                $error("Unexpected extra result frame");
            end
            result_count = result_count+1;
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

        wait (result_count == 5);
        repeat (10) @(posedge clk);
        if (input_count != 5*NFFT || output_count != 5*NFFT ||
                spectrum_count != 5*NFFT) begin
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
        if (errors == 0)
            $display("PASS: five FFT frames verify 10 kHz boundary, fractional frequency and Hann amplitude correction");
        else
            $fatal(1, "FAIL: %0d FFT/spectrum errors", errors);
        $finish;
    end

    initial begin : simulation_timeout
        repeat (1000000) @(posedge clk);
        $fatal(1, "Timeout waiting for FFT spectrum results");
    end

endmodule
