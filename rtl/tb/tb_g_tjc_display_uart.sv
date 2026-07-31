`timescale 1ns/1ps

module tb_g_tjc_display_uart;
    localparam integer CLK_HZ = 1000000;
    localparam integer BAUD = 100000;
    localparam integer CLKS_PER_BIT = CLK_HZ/BAUD;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic uart_rx = 1'b1;
    logic send_button_n = 1'b1;
    logic measurement_valid = 1'b0;
    logic [1:0] component_count = 2'd3;
    logic [23:0] total_vpp_uv = 24'd246800;
    logic [23:0] total_true_rms_uv = 24'd90500;
    logic [19:0] component0_frequency_hz = 20'd12345;
    logic [19:0] component1_frequency_hz = 20'd24000;
    logic [19:0] component2_frequency_hz = 20'd36000;
    logic [23:0] component0_amplitude_uv = 24'd61700;
    logic [23:0] component1_amplitude_uv = 24'd22500;
    logic [23:0] component2_amplitude_uv = 24'd17600;
    logic waveform_display_ready = 1'b1;
    logic waveform_render_busy = 1'b0;
    logic waveform_render_done = 1'b0;
    logic spectrum_display_ready = 1'b1;
    wire [9:0] display_read_addr;
    wire [7:0] waveform_display_data = display_read_addr[7:0];
    wire [7:0] spectrum_display_data = 8'hff-display_read_addr[7:0];

    wire uart_tx;
    wire waveform_render_request;
    wire three_cycle_mode;
    wire spectrum_mode;
    wire calibrate_start;
    wire [23:0] calibration_reference_vpp_uv;
    wire rx_calibrate_command;
    wire rx_framing_error_sticky;
    wire send_button_pressed;
    wire tx_busy;
    wire transfer_busy;
    wire transfer_done;
    wire transparent_timeout_sticky;
    wire request_overrun;

    byte captured [0:4095];
    byte expected [0:4095];
    integer captured_count = 0;
    integer expected_count = 0;
    integer errors = 0;
    integer calibration_pulses = 0;
    integer render_pulses = 0;
    integer transfer_pulses = 0;
    integer i;

    always #500 clk = ~clk;

    g_tjc_display_uart #(
        .CLK_HZ(CLK_HZ), .BAUD(BAUD), .DEBOUNCE_MS(1),
        .HANDSHAKE_TIMEOUT_MS(20)
    ) dut (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .send_button_n(send_button_n),
        .measurement_valid(measurement_valid), .component_count(component_count),
        .total_vpp_uv(total_vpp_uv), .total_true_rms_uv(total_true_rms_uv),
        .component0_frequency_hz(component0_frequency_hz),
        .component1_frequency_hz(component1_frequency_hz),
        .component2_frequency_hz(component2_frequency_hz),
        .component0_amplitude_uv(component0_amplitude_uv),
        .component1_amplitude_uv(component1_amplitude_uv),
        .component2_amplitude_uv(component2_amplitude_uv),
        .waveform_display_ready(waveform_display_ready),
        .waveform_render_busy(waveform_render_busy),
        .waveform_render_done(waveform_render_done),
        .waveform_display_data(waveform_display_data),
        .spectrum_display_ready(spectrum_display_ready),
        .spectrum_display_data(spectrum_display_data),
        .display_read_addr(display_read_addr),
        .waveform_render_request(waveform_render_request),
        .three_cycle_mode(three_cycle_mode), .spectrum_mode(spectrum_mode),
        .calibrate_start(calibrate_start),
        .calibration_reference_vpp_uv(calibration_reference_vpp_uv),
        .rx_calibrate_command(rx_calibrate_command),
        .rx_framing_error_sticky(rx_framing_error_sticky),
        .send_button_pressed(send_button_pressed), .tx_busy(tx_busy),
        .transfer_busy(transfer_busy), .transfer_done(transfer_done),
        .transparent_timeout_sticky(transparent_timeout_sticky),
        .request_overrun(request_overrun)
    );

    always @(posedge clk) begin
        if (calibrate_start) calibration_pulses = calibration_pulses+1;
        if (waveform_render_request) render_pulses = render_pulses+1;
        if (transfer_done) transfer_pulses = transfer_pulses+1;
    end

    task automatic append_string(input string value);
        integer character;
        begin
            for (character = 0; character < value.len(); character++) begin
                expected[expected_count] = value[character];
                expected_count = expected_count+1;
            end
        end
    endtask

    task automatic append_terminator;
        begin
            repeat (3) begin
                expected[expected_count] = 8'hff;
                expected_count = expected_count+1;
            end
        end
    endtask

    task automatic append_full_expected;
        begin
            append_string("x0.val=247"); append_terminator();
            append_string("x1.val=91"); append_terminator();
            append_string("x2.val=62"); append_terminator();
            append_string("x3.val=1235"); append_terminator();
            append_string("x4.val=23"); append_terminator();
            append_string("x5.val=2400"); append_terminator();
            append_string("x6.val=18"); append_terminator();
            append_string("x7.val=3600"); append_terminator();
            append_string("cle s0.id,0"); append_terminator();
            append_string("addt s0.id,0,800"); append_terminator();
            for (i = 0; i < 800; i++) begin
                expected[expected_count] = i[7:0];
                expected_count = expected_count+1;
            end
        end
    endtask

    task automatic send_rx_byte(input byte value);
        integer bit_number;
        begin
            uart_rx = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (bit_number = 0; bit_number < 8; bit_number++) begin
                uart_rx = value[bit_number];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            uart_rx = 1'b1;
            repeat (CLKS_PER_BIT*2) @(posedge clk);
        end
    endtask

    task automatic service_transparent_transfer;
        begin
            wait (dut.tx_state == 4'd4);
            send_rx_byte(8'hfe);
            wait (dut.tx_state == 4'd6);
            wait (!tx_busy);
            send_rx_byte(8'hfd);
            wait (dut.tx_state == 4'd0);
            @(posedge clk);
        end
    endtask

    initial begin : uart_monitor
        byte received;
        integer bit_number;
        forever begin
            @(negedge uart_tx);
            repeat (CLKS_PER_BIT+(CLKS_PER_BIT/2)) @(posedge clk);
            received = 8'd0;
            for (bit_number = 0; bit_number < 8; bit_number++) begin
                received[bit_number] = uart_tx;
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            if (!uart_tx) begin
                errors = errors+1;
                $error("UART TX stop bit was low");
            end
            captured[captured_count] = received;
            captured_count = captured_count+1;
        end
    end

    initial begin
        append_full_expected();
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (8) @(posedge clk);

        measurement_valid = 1'b1;
        @(posedge clk);
        measurement_valid = 1'b0;
        repeat (80) @(posedge clk);

        // Debounced R19 sends all eight values and the current waveform.
        send_button_n = 1'b0;
        repeat (1200) @(posedge clk);
        service_transparent_transfer();
        send_button_n = 1'b1;
        repeat (1200) @(posedge clk);

        if (captured_count != expected_count) begin
            errors = errors+1;
            $error("Full transfer byte count mismatch: got=%0d expected=%0d",
                captured_count, expected_count);
        end
        for (i = 0; i < expected_count && i < captured_count; i++) begin
            if (captured[i] !== expected[i]) begin
                errors = errors+1;
                $error("Full transfer byte %0d mismatch: got=%02x expected=%02x",
                    i, captured[i], expected[i]);
            end
        end

        // Calibration command remains a single ASCII C byte.
        send_rx_byte(8'h43);
        repeat (20) @(posedge clk);

        // '3' selects a three-period waveform and triggers a plot-only redraw.
        send_rx_byte(8'h33);
        repeat (5) @(posedge clk);
        waveform_render_done = 1'b1;
        @(posedge clk);
        waveform_render_done = 1'b0;
        service_transparent_transfer();

        // 'S' selects the spectrum and sends the existing spectrum buffer.
        send_rx_byte(8'h53);
        service_transparent_transfer();

        if (calibration_pulses != 1 ||
                calibration_reference_vpp_uv != 24'd200000 ||
                render_pulses != 1 || !three_cycle_mode || !spectrum_mode ||
                transfer_pulses != 3 || rx_framing_error_sticky ||
                transparent_timeout_sticky || request_overrun) begin
            errors = errors+1;
            $error("Command/status failure: cal=%0d render=%0d transfer=%0d mode=%0b/%0b",
                calibration_pulses, render_pulses, transfer_pulses,
                three_cycle_mode, spectrum_mode);
        end

        if (errors == 0)
            $display("PASS: TJC sends two-decimal-kHz x0..x7, clears s0, debounces R19, switches display modes and completes FE/FD-guarded 800-byte addt transfers");
        else
            $fatal(1, "FAIL: %0d TJC UART errors", errors);
        $finish;
    end

    initial begin
        #800000000;
        $fatal(1, "Timeout in TJC UART self-check");
    end
endmodule
