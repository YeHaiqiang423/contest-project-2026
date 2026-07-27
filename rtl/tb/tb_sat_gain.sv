`timescale 1ns/1ps

module tb_sat_gain;
    localparam int WIDTH = 16;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic in_valid = 1'b0;
    logic signed [WIDTH-1:0] in_data = '0;
    logic out_valid;
    logic signed [WIDTH-1:0] out_data;

    integer input_file;
    integer expected_file;
    integer scan_input;
    integer scan_expected;
    integer input_value;
    integer expected_value;
    integer expected_pending;
    integer checked = 0;
    integer errors = 0;
    bit pending = 1'b0;
    bit finished_driving = 1'b0;

    sat_gain #(.WIDTH(WIDTH), .GAIN(3)) dut (.*);

    always #10 clk = ~clk;

    initial begin
        input_file = $fopen("matlab/vectors/sat_gain_input.txt", "r");
        expected_file = $fopen("matlab/vectors/sat_gain_expected.txt", "r");
        if ((input_file == 0) || (expected_file == 0))
            $fatal(1, "Vector files missing; run MATLAB generator first");

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        while (!$feof(input_file)) begin
            scan_input = $fscanf(input_file, "%d\n", input_value);
            scan_expected = $fscanf(expected_file, "%d\n", expected_value);
            if ((scan_input == 1) && (scan_expected == 1)) begin
                in_valid = 1'b1;
                in_data = input_value;
                expected_pending = expected_value;
                pending = 1'b1;
                @(negedge clk);
            end
        end

        in_valid = 1'b0;
        pending = 1'b0;
        finished_driving = 1'b1;
        repeat (2) @(posedge clk);

        $fclose(input_file);
        $fclose(expected_file);
        if (errors == 0)
            $display("PASS: checked %0d vectors", checked);
        else
            $fatal(1, "FAIL: %0d mismatches in %0d vectors", errors, checked);
        $finish;
    end

    always @(posedge clk) begin
        #1;
        if (out_valid) begin
            checked = checked + 1;
            if ($signed(out_data) !== expected_pending) begin
                errors = errors + 1;
                $error("Mismatch #%0d: got %0d expected %0d", checked,
                    $signed(out_data), expected_pending);
            end
        end
    end

endmodule

