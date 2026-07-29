`timescale 1ns/1ps

module tb_g_processing_pipeline;
    localparam int FRAME_LENGTH = 16;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic capture_enable = 1'b0;
    logic adc_valid = 1'b0;
    logic [13:0] adc_data = '0;
    logic fft_ready = 1'b0;
    logic fft_valid;
    logic signed [15:0] fft_real;
    logic signed [15:0] fft_imag;
    logic fft_last;
    logic frame_done;
    logic [1:0] bank_pending;
    logic adc_input_overrun;
    logic frame_overrun;
    logic scheduler_overrun;
    logic debug_adc_sample_valid;
    logic signed [13:0] debug_adc_sample_data;
    logic debug_fir_output_valid;
    logic signed [15:0] debug_fir_output_data;
    logic debug_frame_ready;
    logic debug_frame_bank;
    logic debug_fft_busy;

    integer adc_file;
    integer expected_file;
    integer scan_count;
    integer adc_value;
    integer expected_value;
    integer adc_count = 0;
    integer output_count = 0;
    integer cycle_count = 0;
    integer errors = 0;
    logic stall_active = 1'b0;
    logic signed [15:0] held_real;
    logic held_last;

    g_processing_pipeline #(
        .FRAME_DECIMATION(4),
        .FRAME_LENGTH(FRAME_LENGTH),
        .FRAME_ADDR_WIDTH(4),
        .HANN_ADDR_WIDTH(3),
        .HANN_COEFF_FILE("matlab/vectors/g_hann_test_q15_unique.hex")
    ) dut (.*);

    always #2.5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            fft_ready <= 1'b0;
        end else begin
            cycle_count <= cycle_count+1;
            fft_ready <= ((cycle_count % 6) != 1) && ((cycle_count % 11) != 4);
        end
    end

    always @(posedge clk) begin
        #1;
        if (fft_valid && !fft_ready) begin
            if (stall_active) begin
                if (($signed(fft_real) !== $signed(held_real)) || (fft_last !== held_last)) begin
                    errors = errors+1;
                    $error("Integrated FFT output changed during backpressure");
                end
            end else begin
                held_real = fft_real;
                held_last = fft_last;
                stall_active = 1'b1;
            end
        end else begin
            stall_active = 1'b0;
        end

        if (fft_valid && fft_ready) begin
            scan_count = $fscanf(expected_file, "%d\n", expected_value);
            if (scan_count != 1)
                $fatal(1, "Pipeline expected vector ended early");
            if ($signed(fft_real) !== expected_value) begin
                errors = errors+1;
                $error("Pipeline output %0d got %0d expected %0d", output_count,
                    $signed(fft_real), expected_value);
            end
            if ($signed(fft_imag) !== 0) begin
                errors = errors+1;
                $error("Pipeline imaginary input must be zero");
            end
            if (fft_last !== (output_count == FRAME_LENGTH-1)) begin
                errors = errors+1;
                $error("Pipeline fft_last mismatch at %0d", output_count);
            end
            output_count = output_count+1;
        end
    end

    initial begin
        adc_file = $fopen("matlab/vectors/g_pipeline_adc_twos.txt", "r");
        expected_file = $fopen("matlab/vectors/g_pipeline_fft_expected.txt", "r");
        if ((adc_file == 0) || (expected_file == 0))
            $fatal(1, "Pipeline vectors missing; run MATLAB generators first");

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        capture_enable = 1'b1;

        while (!$feof(adc_file)) begin
            scan_count = $fscanf(adc_file, "%d\n", adc_value);
            if (scan_count == 1) begin
                adc_data = adc_value;
                adc_valid = 1'b1;
                adc_count = adc_count+1;
                @(negedge clk);
            end
        end
        adc_valid = 1'b0;

        @(posedge frame_done);
        repeat (3) @(posedge clk);
        if (output_count != FRAME_LENGTH) begin
            errors = errors+1;
            $error("Expected %0d integrated outputs, got %0d", FRAME_LENGTH, output_count);
        end
        if (bank_pending != 2'b00) begin
            errors = errors+1;
            $error("Integrated frame bank was not released");
        end
        if (adc_input_overrun || frame_overrun || scheduler_overrun) begin
            errors = errors+1;
            $error("Integrated pipeline reported an overrun");
        end

        $fclose(adc_file);
        $fclose(expected_file);
        if (errors == 0)
            $display("PASS: %0d ADC codes produced %0d verified FFT inputs",
                adc_count, output_count);
        else
            $fatal(1, "FAIL: %0d integrated-pipeline errors", errors);
        $finish;
    end

    initial begin : simulation_timeout
        repeat (10000) @(posedge clk);
        $fatal(1, "Timeout waiting for integrated pipeline completion");
    end

endmodule
