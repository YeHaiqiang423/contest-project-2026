`timescale 1ns/1ps

module tb_g_fft_input_stream;
    localparam int DATA_WIDTH = 16;
    localparam int FRAME_LENGTH = 16;
    localparam int ADDR_WIDTH = 4;
    localparam int COEFF_ADDR_WIDTH = 3;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic start = 1'b0;
    logic start_bank = 1'b1;
    logic busy;
    logic frame_read_enable;
    logic frame_read_bank;
    logic [ADDR_WIDTH-1:0] frame_read_addr;
    logic signed [DATA_WIDTH-1:0] frame_read_data = '0;
    logic fft_valid;
    logic fft_ready = 1'b0;
    logic signed [DATA_WIDTH-1:0] fft_real;
    logic signed [DATA_WIDTH-1:0] fft_imag;
    logic fft_last;
    logic release_valid;
    logic release_bank;

    logic signed [DATA_WIDTH-1:0] frame_memory [0:FRAME_LENGTH-1];
    integer input_file;
    integer expected_file;
    integer scan_count;
    integer input_value;
    integer expected_value;
    integer load_index;
    integer request_count = 0;
    integer output_count = 0;
    integer cycle_count = 0;
    integer errors = 0;
    logic stall_active = 1'b0;
    logic signed [DATA_WIDTH-1:0] held_real;
    logic held_last;

    g_fft_input_stream #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAME_LENGTH(FRAME_LENGTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .COEFF_ADDR_WIDTH(COEFF_ADDR_WIDTH),
        .COEFF_FILE("matlab/vectors/g_hann_test_q15_unique.hex")
    ) dut (.*);

    always #2.5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            fft_ready <= 1'b0;
        end else begin
            cycle_count <= cycle_count+1;
            fft_ready <= ((cycle_count % 5) != 2) && ((cycle_count % 7) != 3);
        end
    end

    always @(posedge clk) begin
        if (frame_read_enable) begin
            if (frame_read_bank !== 1'b1) begin
                errors = errors+1;
                $error("Read request used the wrong bank");
            end
            if (frame_read_addr !== request_count[ADDR_WIDTH-1:0]) begin
                errors = errors+1;
                $error("Read address got %0d expected %0d", frame_read_addr, request_count);
            end
            frame_read_data <= frame_memory[frame_read_addr];
            request_count = request_count+1;
        end
    end

    always @(posedge clk) begin
        #1;
        if (fft_valid && !fft_ready) begin
            if (stall_active) begin
                if (($signed(fft_real) !== $signed(held_real)) || (fft_last !== held_last)) begin
                    errors = errors+1;
                    $error("FFT output changed while back-pressured");
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
                $fatal(1, "Expected Hann vector ended early");
            if ($signed(fft_real) !== expected_value) begin
                errors = errors+1;
                $error("FFT sample %0d got %0d expected %0d", output_count,
                    $signed(fft_real), expected_value);
            end
            if ($signed(fft_imag) !== 0) begin
                errors = errors+1;
                $error("Imaginary input must be zero");
            end
            if (fft_last !== (output_count == FRAME_LENGTH-1)) begin
                errors = errors+1;
                $error("fft_last mismatch at output %0d", output_count);
            end
            output_count = output_count+1;
        end
    end

    initial begin
        input_file = $fopen("matlab/vectors/g_hann_test_input.txt", "r");
        expected_file = $fopen("matlab/vectors/g_hann_test_expected.txt", "r");
        if ((input_file == 0) || (expected_file == 0))
            $fatal(1, "Hann vectors missing; run MATLAB generators first");
        for (load_index = 0; load_index < FRAME_LENGTH; load_index = load_index+1) begin
            scan_count = $fscanf(input_file, "%d\n", input_value);
            if (scan_count != 1)
                $fatal(1, "Hann input vector ended early");
            frame_memory[load_index] = input_value;
        end

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        @(posedge release_valid);
        #1;
        if (!release_valid || (release_bank !== 1'b1)) begin
            errors = errors+1;
            $error("Completed frame did not release bank one");
        end
        if ((request_count != FRAME_LENGTH) || (output_count != FRAME_LENGTH)) begin
            errors = errors+1;
            $error("Expected %0d requests/outputs, got %0d/%0d",
                FRAME_LENGTH, request_count, output_count);
        end
        if (busy) begin
            errors = errors+1;
            $error("busy must clear after final transfer");
        end

        $fclose(input_file);
        $fclose(expected_file);
        if (errors == 0)
            $display("PASS: %0d Hann-windowed FFT inputs verified with backpressure", output_count);
        else
            $fatal(1, "FAIL: %0d FFT-input errors", errors);
        $finish;
    end

    initial begin : simulation_timeout
        repeat (1000) @(posedge clk);
        $fatal(1, "Timeout waiting for FFT input stream completion");
    end

endmodule
