`timescale 1ns/1ps

module tb_g_measurement_stabilizer;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic measurement_valid = 1'b0;
    logic [1:0] count_in = 2'd1;
    logic [19:0] f0 = 20'd500000;
    logic [19:0] f1 = 20'd0;
    logic [19:0] f2 = 20'd0;
    logic [23:0] a0 = 24'd100000;
    logic [23:0] a1 = 24'd0;
    logic [23:0] a2 = 24'd0;
    logic [23:0] rms = 24'd70711;

    wire stable_valid;
    wire stable_locked;
    wire [1:0] count_out;
    wire [19:0] stable_f0;
    wire [19:0] stable_f1;
    wire [19:0] stable_f2;
    wire [23:0] stable_a0;
    wire [23:0] stable_a1;
    wire [23:0] stable_a2;
    wire [23:0] stable_rms;
    integer errors = 0;
    integer stable_count = 0;

    always #2.5 clk = ~clk;

    g_measurement_stabilizer dut (
        .clk(clk), .rst_n(rst_n), .measurement_valid(measurement_valid),
        .component_count_in(count_in),
        .component0_frequency_hz_in(f0), .component1_frequency_hz_in(f1),
        .component2_frequency_hz_in(f2),
        .component0_amplitude_uv_in(a0), .component1_amplitude_uv_in(a1),
        .component2_amplitude_uv_in(a2), .total_true_rms_uv_in(rms),
        .stable_valid(stable_valid), .stable_locked(stable_locked),
        .component_count(count_out),
        .component0_frequency_hz(stable_f0),
        .component1_frequency_hz(stable_f1),
        .component2_frequency_hz(stable_f2),
        .component0_amplitude_uv(stable_a0),
        .component1_amplitude_uv(stable_a1),
        .component2_amplitude_uv(stable_a2),
        .total_true_rms_uv(stable_rms)
    );

    always @(posedge clk)
        if (stable_valid)
            stable_count = stable_count+1;

    task automatic pulse_frame;
        begin
            @(negedge clk);
            measurement_valid = 1'b1;
            @(negedge clk);
            measurement_valid = 1'b0;
            repeat (5) @(posedge clk);
        end
    endtask

    initial begin
        repeat (6) @(posedge clk);
        rst_n = 1'b1;
        // Vivado launches behavioral simulation for 1000 ns before the Tcl
        // script issues "run all"; keep the self-check alive across that split.
        repeat (220) @(posedge clk);

        // First frame is a candidate only.
        pulse_frame();
        if (stable_count != 0 || stable_locked) begin
            errors = errors+1;
            $error("First frame was incorrectly published");
        end

        // A matching second frame becomes visible.
        f0 = 20'd499950;
        a0 = 24'd101000;
        rms = 24'd71400;
        pulse_frame();
        if (stable_count != 1 || !stable_locked ||
                stable_f0 != 20'd499950 || stable_a0 != 24'd101000) begin
            errors = errors+1;
            $error("Matching frame pair was not published");
        end

        // One transition frame must break lock and remain hidden.
        f0 = 20'd400000;
        a0 = 24'd92000;
        rms = 24'd65000;
        pulse_frame();
        if (stable_count != 1 || stable_locked) begin
            errors = errors+1;
            $error("Transition frame was not rejected");
        end

        // The second frame at the new setting restores a stable result.
        f0 = 20'd400050;
        a0 = 24'd92500;
        rms = 24'd65400;
        pulse_frame();
        if (stable_count != 2 || !stable_locked ||
                count_out != 1 || stable_f0 != 20'd400050) begin
            errors = errors+1;
            $error("New stable setting was not accepted");
        end

        if (errors == 0)
            $display("PASS: two-frame stability gate rejects transition data and publishes stable measurements");
        else
            $fatal(1, "FAIL: %0d measurement stabilizer errors", errors);
        $finish;
    end
endmodule
