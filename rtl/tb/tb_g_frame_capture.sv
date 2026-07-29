`timescale 1ns/1ps

module tb_g_frame_capture;
    localparam int DATA_WIDTH = 16;
    localparam int DECIMATION = 4;
    localparam int FRAME_LENGTH = 16;
    localparam int ADDR_WIDTH = 4;
    localparam int FRAME_COUNT = 2;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic capture_enable = 1'b0;
    logic sample_valid = 1'b0;
    logic signed [DATA_WIDTH-1:0] sample_data = '0;
    logic frame_ready;
    logic frame_bank;
    logic [1:0] bank_pending;
    logic capture_stalled;
    logic frame_overrun;
    logic read_enable = 1'b0;
    logic read_bank = 1'b0;
    logic [ADDR_WIDTH-1:0] read_addr = '0;
    logic signed [DATA_WIDTH-1:0] read_data;
    logic release_valid = 1'b0;
    logic release_bank = 1'b0;

    integer input_file;
    integer expected_file;
    integer scan_count;
    integer input_value;
    integer expected_value;
    integer input_count = 0;
    integer output_count = 0;
    integer errors = 0;
    integer frame_index;
    integer address_index;
    logic observed_bank;

    g_frame_capture #(
        .DATA_WIDTH(DATA_WIDTH),
        .DECIMATION(DECIMATION),
        .FRAME_LENGTH(FRAME_LENGTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (.*);

    always #2.5 clk = ~clk;

    initial begin
        input_file = $fopen("matlab/vectors/g_frame_input.txt", "r");
        expected_file = $fopen("matlab/vectors/g_frame_expected.txt", "r");
        if ((input_file == 0) || (expected_file == 0))
            $fatal(1, "Frame vectors missing; run MATLAB generators first");

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        capture_enable = 1'b1;

        fork
            begin : input_driver
                while (!$feof(input_file)) begin
                    scan_count = $fscanf(input_file, "%d\n", input_value);
                    if (scan_count == 1) begin
                        sample_data = input_value;
                        sample_valid = 1'b1;
                        input_count = input_count+1;
                        @(negedge clk);
                        sample_valid = 1'b0;
                        repeat (9) @(negedge clk);
                    end
                end
            end

            begin : frame_reader
                for (frame_index = 0; frame_index < FRAME_COUNT;
                        frame_index = frame_index+1) begin
                    @(posedge frame_ready);
                    #1;
                    observed_bank = frame_bank;
                    if (observed_bank !== frame_index[0]) begin
                        errors = errors+1;
                        $error("Frame %0d used bank %0d, expected %0d",
                            frame_index, observed_bank, frame_index[0]);
                    end

                    for (address_index = 0; address_index < FRAME_LENGTH;
                            address_index = address_index+1) begin
                        scan_count = $fscanf(expected_file, "%d\n", expected_value);
                        if (scan_count != 1)
                            $fatal(1, "Expected vector ended early");
                        @(negedge clk);
                        read_enable = 1'b1;
                        read_bank = observed_bank;
                        read_addr = address_index;
                        @(posedge clk);
                        #1;
                        output_count = output_count+1;
                        if ($signed(read_data) !== expected_value) begin
                            errors = errors+1;
                            $error("Frame %0d address %0d: got %0d expected %0d",
                                frame_index, address_index, $signed(read_data), expected_value);
                        end
                    end
                    @(negedge clk);
                    read_enable = 1'b0;
                    release_bank = observed_bank;
                    release_valid = 1'b1;
                    @(negedge clk);
                    release_valid = 1'b0;
                end
            end
        join

        repeat (5) @(posedge clk);
        $fclose(input_file);
        $fclose(expected_file);
        if (capture_stalled || frame_overrun) begin
            errors = errors+1;
            $error("Unexpected capture stall or overrun");
        end
        if (bank_pending != 2'b00) begin
            errors = errors+1;
            $error("All read banks should have been released");
        end

        if (errors == 0)
            $display("PASS: %0d inputs produced %0d verified frame samples",
                input_count, output_count);
        else
            $fatal(1, "FAIL: %0d frame-capture errors", errors);
        $finish;
    end

endmodule
