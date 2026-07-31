`timescale 1ns/1ps

module tb_g_spectrum_display;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic spectrum_valid = 1'b0;
    logic [11:0] spectrum_bin = 12'd0;
    logic [32:0] spectrum_power = 33'd0;
    logic [9:0] display_read_addr = 10'd0;

    wire [7:0] display_read_data;
    wire display_ready;
    wire frame_done;
    wire processing_busy;
    wire capture_overrun;
    integer errors = 0;
    integer bin_index;

    always #2.5 clk = ~clk;

    g_spectrum_display dut (
        .clk(clk), .rst_n(rst_n),
        .spectrum_valid(spectrum_valid), .spectrum_bin(spectrum_bin),
        .spectrum_power(spectrum_power),
        .display_read_addr(display_read_addr),
        .display_read_data(display_read_data),
        .display_ready(display_ready), .frame_done(frame_done),
        .processing_busy(processing_busy), .capture_overrun(capture_overrun)
    );

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        for (bin_index = 0; bin_index <= 1229; bin_index++) begin
            @(negedge clk);
            spectrum_bin = bin_index;
            if (bin_index == 128)
                spectrum_power = 33'd1000000; // magnitude 1000
            else if (bin_index == 512)
                spectrum_power = 33'd250000;  // magnitude 500
            else if (bin_index == 1229)
                spectrum_power = 33'd562500;  // magnitude 750 at 600 kHz
            else
                spectrum_power = 33'd100;     // magnitude 10
            spectrum_valid = 1'b1;
            @(posedge clk);
        end
        @(negedge clk);
        spectrum_valid = 1'b0;
        wait (frame_done);

        display_read_addr = 102;
        @(posedge clk);
        #1;
        if (display_read_data < 250) begin
            errors = errors+1;
            $error("Strong spectrum peak was not normalized to full scale: %0d",
                display_read_data);
        end
        display_read_addr = 337;
        @(posedge clk);
        #1;
        if (display_read_data < 124 || display_read_data > 132) begin
            errors = errors+1;
            $error("Half-amplitude spectrum peak mismatch: %0d",
                display_read_data);
        end
        display_read_addr = 775;
        @(posedge clk);
        #1;
        if (display_read_data < 187 || display_read_data > 195) begin
            errors = errors+1;
            $error("600 kHz edge peak or right margin mismatch: %0d",
                display_read_data);
        end
        display_read_addr = 700;
        @(posedge clk);
        #1;
        if (display_read_data > 5) begin
            errors = errors+1;
            $error("Spectrum floor unexpectedly high: %0d", display_read_data);
        end
        display_read_addr = 0;
        @(posedge clk);
        #1;
        if (display_read_data != 0) begin
            errors = errors+1;
            $error("Left spectrum margin was not blank: %0d",
                display_read_data);
        end
        display_read_addr = 799;
        @(posedge clk);
        #1;
        if (display_read_data != 0) begin
            errors = errors+1;
            $error("Right spectrum margin was not blank: %0d",
                display_read_data);
        end
        if (capture_overrun) begin
            errors = errors+1;
            $error("Unexpected spectrum capture overrun");
        end

        if (errors == 0)
            $display("PASS: 0..600 kHz spectrum is max-pooled with symmetric 24-point display margins");
        else
            $fatal(1, "FAIL: %0d spectrum display errors", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("DEBUG state=%0d capture_active=%0b flush=%0b complete=%0b process_point=%0d busy=%0b max=%0d",
            dut.state, dut.capture_active, dut.capture_flush_pending,
            dut.capture_complete, dut.process_point, processing_busy,
            dut.frame_maximum);
        $fatal(1, "Timeout in spectrum display self-check");
    end
endmodule
