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
    logic [1:0] component_count = 2'd0;
    logic [19:0] component0_frequency_hz = 20'd0;
    logic [19:0] component1_frequency_hz = 20'd0;
    logic [23:0] component0_amplitude_uv = 24'd0;
    logic [23:0] component1_amplitude_uv = 24'd0;

    wire uart_tx;
    wire calibrate_start;
    wire [23:0] calibration_reference_vpp_uv;
    wire rx_calibrate_command;
    wire rx_framing_error_sticky;
    wire send_button_pressed;
    wire tx_busy;

    byte captured [0:255];
    byte expected [0:63];
    integer captured_count = 0;
    integer expected_count = 0;
    integer calibration_pulses = 0;
    integer errors = 0;
    integer i;

    always #500 clk = ~clk;

    g_tjc_display_uart #(
        .CLK_HZ(CLK_HZ), .BAUD(BAUD), .DEBOUNCE_MS(1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .send_button_n(send_button_n),
        .measurement_valid(measurement_valid),
        .component_count(component_count),
        .component0_frequency_hz(component0_frequency_hz),
        .component1_frequency_hz(component1_frequency_hz),
        .component0_amplitude_uv(component0_amplitude_uv),
        .component1_amplitude_uv(component1_amplitude_uv),
        .calibrate_start(calibrate_start),
        .calibration_reference_vpp_uv(calibration_reference_vpp_uv),
        .rx_calibrate_command(rx_calibrate_command),
        .rx_framing_error_sticky(rx_framing_error_sticky),
        .send_button_pressed(send_button_pressed), .tx_busy(tx_busy),
        .transmitted_component_count(),
        .transmitted_fundamental_frequency_hz(),
        .transmitted_harmonic_frequency_hz(),
        .transmitted_fundamental_amplitude_uv(),
        .transmitted_harmonic_amplitude_uv()
    );

    always @(posedge clk) begin
        if (calibrate_start)
            calibration_pulses = calibration_pulses+1;
    end

    task automatic append_command(
        input byte object_digit,
        input byte d0, input byte d1, input byte d2,
        input byte d3, input byte d4, input byte d5
    );
        byte digits [0:5];
        integer first;
        integer digit_number;
        begin
            digits[0] = d0;
            digits[1] = d1;
            digits[2] = d2;
            digits[3] = d3;
            digits[4] = d4;
            digits[5] = d5;
            first = 0;
            while (first < 5 && digits[first] == "0")
                first = first+1;
            expected[expected_count+0] = "x";
            expected[expected_count+1] = object_digit;
            expected[expected_count+2] = ".";
            expected[expected_count+3] = "v";
            expected[expected_count+4] = "a";
            expected[expected_count+5] = "l";
            expected[expected_count+6] = "=";
            for (digit_number = first; digit_number < 6;
                    digit_number = digit_number+1)
                expected[expected_count+7+digit_number-first] =
                    digits[digit_number];
            expected[expected_count+13-first] = 8'hff;
            expected[expected_count+14-first] = 8'hff;
            expected[expected_count+15-first] = 8'hff;
            expected_count = expected_count+16-first;
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

    // Decode the DUT TX at each bit centre.
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
        append_command("0", "0", "0", "0", "1", "2", "3");
        append_command("2", "0", "1", "2", "3", "4", "5");
        append_command("3", "0", "0", "0", "0", "4", "5");
        append_command("4", "0", "2", "4", "0", "0", "0");

        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (8) @(posedge clk);

        // Peak amplitudes 61.7 mV and 22.5 mV become rounded Vpp values
        // 123 mV and 45 mV. Frequencies are sent as raw integer Hz.
        component_count = 2'd2;
        component0_frequency_hz = 20'd12345;
        component1_frequency_hz = 20'd24000;
        component0_amplitude_uv = 24'd61700;
        component1_amplitude_uv = 24'd22500;
        measurement_valid = 1'b1;
        @(posedge clk);
        measurement_valid = 1'b0;
        repeat (80) @(posedge clk);

        // A short bounce must not send anything.
        send_button_n = 1'b0;
        repeat (200) @(posedge clk);
        send_button_n = 1'b1;
        repeat (200) @(posedge clk);
        if (captured_count != 0) begin
            errors = errors+1;
            $error("Short button bounce started a transfer");
        end

        // Stable active-low press starts exactly one four-command transaction.
        send_button_n = 1'b0;
        repeat (1200) @(posedge clk);
        wait (captured_count == expected_count);
        repeat (100) @(posedge clk);
        for (i = 0; i < expected_count; i = i+1) begin
            if (captured[i] !== expected[i]) begin
                errors = errors+1;
                $error("TX byte %0d mismatch: got %02x expected %02x",
                    i, captured[i], expected[i]);
            end
        end

        // Holding the button cannot retrigger.
        repeat (2000) @(posedge clk);
        if (captured_count != expected_count) begin
            errors = errors+1;
            $error("Held button retriggered the UART transfer");
        end
        send_button_n = 1'b1;
        repeat (1200) @(posedge clk);

        // Screen calibration button sends a single ASCII C byte.
        send_rx_byte(8'h43);
        repeat (20) @(posedge clk);
        if (calibration_pulses != 1 ||
                calibration_reference_vpp_uv != 24'd200000 ||
                rx_framing_error_sticky) begin
            errors = errors+1;
            $error("Calibration command decode failed");
        end

        if (errors == 0)
            $display("PASS: debounced R19 sends x0/x2/x3/x4 once and screen byte 0x43 triggers 200 mVpp calibration");
        else
            $fatal(1, "FAIL: %0d TJC UART errors", errors);
        $finish;
    end

    initial begin
        #30000000;
        $fatal(1, "Timeout in TJC UART self-check");
    end

endmodule
