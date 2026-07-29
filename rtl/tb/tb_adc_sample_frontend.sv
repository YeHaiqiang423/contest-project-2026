`timescale 1ns/1ps

module tb_adc_sample_frontend;
    localparam int ADC_WIDTH = 14;
    localparam int DECIMATION = 10;

    logic clk_adc = 1'b0;
    logic rst_n = 1'b0;
    logic adc_valid = 1'b0;
    logic [ADC_WIDTH-1:0] adc_data_twos = '0;
    logic [ADC_WIDTH-1:0] adc_data_offset = '0;
    logic sample_valid_twos;
    logic signed [ADC_WIDTH-1:0] sample_data_twos;
    logic sample_valid_offset;
    logic signed [ADC_WIDTH-1:0] sample_data_offset;

    integer vector_file;
    integer scan_count;
    integer vector_valid;
    integer vector_twos;
    integer vector_offset;
    integer vector_expected_valid;
    integer vector_expected_value;
    integer checked = 0;
    integer errors = 0;

    adc_sample_frontend #(
        .ADC_WIDTH(ADC_WIDTH),
        .DECIMATION(DECIMATION),
        .INPUT_OFFSET_BINARY(0)
    ) dut_twos (
        .clk_adc(clk_adc),
        .rst_n(rst_n),
        .adc_valid(adc_valid),
        .adc_data(adc_data_twos),
        .sample_valid(sample_valid_twos),
        .sample_data(sample_data_twos)
    );

    adc_sample_frontend #(
        .ADC_WIDTH(ADC_WIDTH),
        .DECIMATION(DECIMATION),
        .INPUT_OFFSET_BINARY(1)
    ) dut_offset (
        .clk_adc(clk_adc),
        .rst_n(rst_n),
        .adc_valid(adc_valid),
        .adc_data(adc_data_offset),
        .sample_valid(sample_valid_offset),
        .sample_data(sample_data_offset)
    );

    always #2.5 clk_adc = ~clk_adc;

    initial begin
        vector_file = $fopen("matlab/vectors/adc_sample_frontend_vectors.txt", "r");
        if (vector_file == 0)
            $fatal(1, "Vector file missing; run MATLAB vector generator first");

        repeat (4) @(posedge clk_adc);
        @(negedge clk_adc);
        rst_n = 1'b1;

        while (!$feof(vector_file)) begin
            scan_count = $fscanf(vector_file, "%d %d %d %d %d\n",
                vector_valid, vector_twos, vector_offset,
                vector_expected_valid, vector_expected_value);
            if (scan_count == 5) begin
                adc_valid = vector_valid;
                adc_data_twos = vector_twos;
                adc_data_offset = vector_offset;
                @(posedge clk_adc);
                #1;
                check_outputs();
                @(negedge clk_adc);
            end
        end

        adc_valid = 1'b0;
        repeat (2) @(posedge clk_adc);
        $fclose(vector_file);
        if (errors == 0)
            $display("PASS: checked %0d ADS6149 front-end cycles", checked);
        else
            $fatal(1, "FAIL: %0d mismatches in %0d cycles", errors, checked);
        $finish;
    end

    task check_outputs;
        begin
            checked = checked+1;
            if (sample_valid_twos !== vector_expected_valid) begin
                errors = errors+1;
                $error("Two's valid mismatch at cycle %0d", checked);
            end
            if (sample_valid_offset !== vector_expected_valid) begin
                errors = errors+1;
                $error("Offset valid mismatch at cycle %0d", checked);
            end
            if (vector_expected_valid) begin
                if ($signed(sample_data_twos) !== vector_expected_value) begin
                    errors = errors+1;
                    $error("Two's data mismatch at cycle %0d: got %0d expected %0d",
                        checked, $signed(sample_data_twos), vector_expected_value);
                end
                if ($signed(sample_data_offset) !== vector_expected_value) begin
                    errors = errors+1;
                    $error("Offset data mismatch at cycle %0d: got %0d expected %0d",
                        checked, $signed(sample_data_offset), vector_expected_value);
                end
            end
        end
    endtask

endmodule
