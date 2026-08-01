`timescale 1ns/1ps

module tb_g_cordic_atan2;
    localparam int INPUT_WIDTH = 48;
    // Keep generated real-to-integer values inside $rtoi's signed 32-bit
    // range while retaining ample precision for sub-degree checking.
    localparam longint signed SCALE = 64'sd100000000;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic start = 1'b0;
    logic signed [INPUT_WIDTH-1:0] x_in = '0;
    logic signed [INPUT_WIDTH-1:0] y_in = '0;
    wire busy;
    wire done;
    wire [15:0] angle_q16;

    integer errors = 0;
    integer checks = 0;

    always #2.5 clk = ~clk;

    g_cordic_atan2 #(
        .INPUT_WIDTH(INPUT_WIDTH),
        .ITERATIONS(18)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .x_in(x_in), .y_in(y_in),
        .busy(busy), .done(done), .angle_q16(angle_q16)
    );

    function automatic integer q16_to_integer_degrees;
        input [15:0] angle;
        reg [24:0] scaled;
        integer result;
        begin
            scaled = angle*9'd360+25'd32768;
            result = scaled >> 16;
            q16_to_integer_degrees = (result == 360) ? 0 : result;
        end
    endfunction

    task automatic run_vector;
        input integer expected_degrees;
        input longint signed x_value;
        input longint signed y_value;
        integer timeout;
        integer measured_degrees;
        begin
            while (busy)
                @(posedge clk);
            @(negedge clk);
            x_in = x_value[INPUT_WIDTH-1:0];
            y_in = y_value[INPUT_WIDTH-1:0];
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            timeout = 0;
            while (!done && timeout < 100) begin
                @(posedge clk);
                timeout = timeout+1;
            end

            checks = checks+1;
            if (!done) begin
                errors = errors+1;
                $error("CORDIC timeout at expected angle %0d", expected_degrees);
            end else begin
                measured_degrees = q16_to_integer_degrees(angle_q16);
                if (measured_degrees != expected_degrees) begin
                    errors = errors+1;
                    $error("Angle mismatch x=%0d y=%0d expected=%0d measured=%0d q16=0x%04h",
                        x_value, y_value, expected_degrees,
                        measured_degrees, angle_q16);
                end
            end
            // Sample between clock edges so the DUT's nonblocking done<=0
            // assignment from the following rising edge has taken effect.
            @(negedge clk);
            if (done) begin
                errors = errors+1;
                $error("done did not return low after its one-cycle pulse");
            end
        end
    endtask

    task automatic run_degree;
        input integer expected_degrees;
        real radians;
        longint signed x_value;
        longint signed y_value;
        begin
            radians = expected_degrees*3.14159265358979323846/180.0;
            // The phase estimator maps x=S=A*cos(phi), y=C=A*sin(phi), so
            // atan2(y,x) must return the requested sine-series phase phi.
            x_value = $rtoi($cos(radians)*SCALE);
            y_value = $rtoi($sin(radians)*SCALE);
            run_vector(expected_degrees, x_value, y_value);
        end
    endtask

    initial begin
        repeat (6) @(posedge clk);
        rst_n = 1'b1;
        // launch_simulation advances 1000 ns before the Tcl script runs all.
        repeat (220) @(posedge clk);

        // All four defined axis directions. atan2(0,0) is undefined and the
        // phase estimator rejects a zero correlation before using its angle.
        run_vector(0,   SCALE,  0);
        run_vector(90,  0,      SCALE);
        run_vector(180, -SCALE, 0);
        run_vector(270, 0,      -SCALE);

        // Interior points cover all quadrants, near-axis cases and exact
        // diagonal directions. Integer-degree conversion must be exact.
        run_degree(1);
        run_degree(30);
        run_degree(45);
        run_degree(89);
        run_degree(91);
        run_degree(120);
        run_degree(135);
        run_degree(179);
        run_degree(181);
        run_degree(225);
        run_degree(269);
        run_degree(271);
        run_degree(300);
        run_degree(315);
        run_degree(359);

        if (errors == 0)
            $display("PASS: CORDIC atan2 checked %0d vectors across four quadrants and all axes", checks);
        else
            $fatal(1, "FAIL: %0d of %0d CORDIC checks failed", errors, checks);
        $finish;
    end
endmodule
