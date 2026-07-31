`timescale 1ns/1ps

module tb_g_time_domain_display;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic sample_valid = 1'b0;
    logic signed [15:0] sample_data = 16'sd0;
    logic measurement_valid = 1'b0;
    logic [19:0] fundamental_frequency_hz = 20'd100000;
    logic [23:0] active_gain_q16 = 24'd1638400; // 25 uV/code
    logic render_request = 1'b0;
    logic render_three_cycles = 1'b0;
    logic [9:0] display_read_addr = 10'd0;

    wire [7:0] display_read_data;
    wire display_ready;
    wire render_busy;
    wire render_done;
    wire request_overrun;
    wire total_vpp_valid;
    wire [15:0] total_vpp_code;
    wire [23:0] total_vpp_uv;

    integer errors = 0;
    integer sample_index;
    integer point_index;
    integer crossings;
    integer minimum_level;
    integer maximum_level;
    integer previous_level;
    integer repeated_neighbors;
    real sample_real;

    always #2.5 clk = ~clk;

    g_time_domain_display dut (
        .clk(clk), .rst_n(rst_n),
        .sample_valid(sample_valid), .sample_data(sample_data),
        .measurement_valid(measurement_valid),
        .fundamental_frequency_hz(fundamental_frequency_hz),
        .active_gain_q16(active_gain_q16),
        .render_request(render_request),
        .render_three_cycles(render_three_cycles),
        .display_read_addr(display_read_addr),
        .display_read_data(display_read_data),
        .display_ready(display_ready), .render_busy(render_busy),
        .render_done(render_done), .request_overrun(request_overrun),
        .total_vpp_valid(total_vpp_valid),
        .total_vpp_code(total_vpp_code), .total_vpp_uv(total_vpp_uv)
    );

    task automatic check_waveform(
        input integer expected_crossings,
        input integer require_smooth
    );
        begin
            crossings = 0;
            repeated_neighbors = 0;
            minimum_level = 255;
            maximum_level = 0;
            display_read_addr = 0;
            #1;
            previous_level = display_read_data;
            for (point_index = 0; point_index < 800; point_index++) begin
                display_read_addr = point_index;
                #1;
                if (display_read_data < minimum_level)
                    minimum_level = display_read_data;
                if (display_read_data > maximum_level)
                    maximum_level = display_read_data;
                if (previous_level < 128 && display_read_data >= 128)
                    crossings = crossings+1;
                if (point_index != 0 && previous_level == display_read_data)
                    repeated_neighbors = repeated_neighbors+1;
                previous_level = display_read_data;
            end
            if (minimum_level > 2 || maximum_level < 253) begin
                errors = errors+1;
                $error("Waveform normalization failed: min=%0d max=%0d",
                    minimum_level, maximum_level);
            end
            if (crossings < expected_crossings-1 ||
                    crossings > expected_crossings+1) begin
                errors = errors+1;
                $error("Waveform cycle count failed: crossings=%0d expected=%0d",
                    crossings, expected_crossings);
            end
            // Eight-bit vertical quantization still repeats samples near the
            // extrema.  Linear interpolation must nevertheless cut the old
            // nearest-neighbor staircase (about 600 repeats here) materially.
            if (require_smooth && repeated_neighbors > 400) begin
                errors = errors+1;
                $error("Waveform still contains nearest-neighbor staircases: repeated=%0d",
                    repeated_neighbors);
            end
        end
    endtask

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1'b1;

        // 20 MSPS stream represented by one valid pulse per ten 200 MHz clocks.
        // 100 kHz therefore has exactly 200 valid samples per period.
        for (sample_index = 0; sample_index < 8300; sample_index++) begin
            sample_real = 1000.0*$sin(6.283185307179586*sample_index/200.0);
            sample_data = $rtoi(sample_real);
            sample_valid = 1'b1;
            @(posedge clk);
            sample_valid = 1'b0;
            repeat (9) @(posedge clk);
        end

        measurement_valid = 1'b1;
        @(posedge clk);
        measurement_valid = 1'b0;
        wait (total_vpp_valid);
        if (total_vpp_code < 1998 || total_vpp_code > 2002 ||
                total_vpp_uv < 49900 || total_vpp_uv > 50100) begin
            errors = errors+1;
            $error("Composite Vpp failed: code=%0d uv=%0d",
                total_vpp_code, total_vpp_uv);
        end
        wait (render_done);
        check_waveform(1, 1);

        repeat (4) @(posedge clk);
        @(negedge clk);
        render_three_cycles = 1'b1;
        render_request = 1'b1;
        @(negedge clk);
        render_request = 1'b0;
        wait (render_done);
        check_waveform(3, 0);

        // A request arriving before its frequency prerequisite becomes valid
        // must be retained rather than disappearing as a one-cycle pulse.
        fundamental_frequency_hz = 20'd0;
        render_three_cycles = 1'b0;
        @(negedge clk);
        render_request = 1'b1;
        @(negedge clk);
        render_request = 1'b0;
        repeat (20) @(posedge clk);
        fundamental_frequency_hz = 20'd100000;
        wait (render_done);

        if (request_overrun) begin
            errors = errors+1;
            $error("Unexpected time-display request overrun");
        end

        if (errors == 0)
            $display("PASS: calibrated Vpp, retained render requests and interpolated 1/3-cycle waveforms");
        else
            $fatal(1, "FAIL: %0d time-domain display errors", errors);
        $finish;
    end

    initial begin
        #6000000;
        $display("DEBUG timeout state=%0d pending=%0b busy=%0b done=%0b frequency=%0d point=%0d",
            dut.state, dut.pending_render_request, render_busy, render_done,
            fundamental_frequency_hz, dut.render_point);
        $fatal(1, "Timeout in time-domain display self-check");
    end
endmodule
