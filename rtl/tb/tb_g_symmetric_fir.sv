`timescale 1ns/1ps

module tb_g_symmetric_fir;
    localparam int INPUT_WIDTH = 14;
    localparam int OUTPUT_WIDTH = 16;
    localparam int MAX_VECTORS = 1024;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic sample_valid = 1'b0;
    logic signed [INPUT_WIDTH-1:0] sample_data = '0;
    logic output_valid;
    logic signed [OUTPUT_WIDTH-1:0] output_data;
    logic input_overrun;

    integer vector_file;
    integer scan_count;
    integer input_value;
    integer expected_value;
    integer expected_memory [0:MAX_VECTORS-1];
    integer input_count = 0;
    integer output_count = 0;
    integer errors = 0;
    integer timeout_cycles = 0;

    g_symmetric_fir dut (.*);
    always #2.5 clk = ~clk;

    initial begin
        vector_file = $fopen("matlab/vectors/g_fir_vectors.txt", "r");
        if (vector_file == 0)
            $fatal(1, "FIR vectors missing; run MATLAB generators first");

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        while (!$feof(vector_file)) begin
            scan_count = $fscanf(vector_file, "%d %d\n", input_value, expected_value);
            if (scan_count == 2) begin
                if (input_count >= MAX_VECTORS)
                    $fatal(1, "Increase MAX_VECTORS");
                expected_memory[input_count] = expected_value;
                input_count = input_count+1;
                sample_data = input_value;
                sample_valid = 1'b1;
                @(negedge clk);
                sample_valid = 1'b0;
                repeat (9) @(negedge clk);
            end
        end
        $fclose(vector_file);

        while ((output_count < input_count) && (timeout_cycles < 100)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles+1;
        end
        if (output_count != input_count) begin
            errors = errors+1;
            $error("Output timeout: got %0d of %0d", output_count, input_count);
        end
        if (input_overrun) begin
            errors = errors+1;
            $error("DUT reported input overrun for a 10-clock cadence");
        end

        if (errors == 0)
            $display("PASS: checked %0d bit-true FIR outputs", output_count);
        else
            $fatal(1, "FAIL: %0d FIR errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        #1;
        if (output_valid) begin
            if (output_count >= input_count) begin
                errors = errors+1;
                $error("Unexpected output %0d", $signed(output_data));
            end else if ($signed(output_data) !== expected_memory[output_count]) begin
                errors = errors+1;
                $error("Mismatch #%0d: got %0d expected %0d", output_count,
                    $signed(output_data), expected_memory[output_count]);
            end
            output_count = output_count+1;
        end
    end

endmodule
