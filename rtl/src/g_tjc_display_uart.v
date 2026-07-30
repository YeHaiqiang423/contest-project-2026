`timescale 1ns/1ps

// TJC4827T143 measurement-page adapter.
// Screen command on button release: printh 43  (ASCII 'C').
// FPGA updates x0/x2/x3/x4 with TJC ASCII assignments terminated by FF FF FF.
module g_tjc_display_uart #(
    parameter integer CLK_HZ = 200000000,
    parameter integer BAUD = 115200,
    parameter integer DEBOUNCE_MS = 20
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,
    output wire        uart_tx,
    input  wire        send_button_n,

    input  wire        measurement_valid,
    input  wire [1:0]  component_count,
    input  wire [19:0] component0_frequency_hz,
    input  wire [19:0] component1_frequency_hz,
    input  wire [23:0] component0_amplitude_uv,
    input  wire [23:0] component1_amplitude_uv,

    output reg         calibrate_start,
    output wire [23:0] calibration_reference_vpp_uv,
    output reg         rx_calibrate_command,
    output reg         rx_framing_error_sticky,
    output reg         send_button_pressed,
    output wire        tx_busy,
    output reg  [1:0]  transmitted_component_count,
    output reg  [19:0] transmitted_fundamental_frequency_hz,
    output reg  [19:0] transmitted_harmonic_frequency_hz,
    output reg  [23:0] transmitted_fundamental_amplitude_uv,
    output reg  [23:0] transmitted_harmonic_amplitude_uv
);

    localparam integer DEBOUNCE_CYCLES =
        (CLK_HZ/1000)*DEBOUNCE_MS;

    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_framing_error;
    reg tx_start;
    reg [7:0] tx_data;
    wire tx_done;

    reg bcd_start;
    wire bcd0_valid;
    wire bcd2_valid;
    wire bcd3_valid;
    wire bcd4_valid;
    wire [31:0] bcd0;
    wire [31:0] bcd2;
    wire [31:0] bcd3;
    wire [31:0] bcd4;
    wire [24:0] rounded_vpp0_uv;
    wire [24:0] rounded_vpp1_uv;

    reg have_snapshot;
    reg [31:0] bcd_x0;
    reg [31:0] bcd_x2;
    reg [31:0] bcd_x3;
    reg [31:0] bcd_x4;
    reg [2:0] field_index;
    reg [2:0] digit_start;
    reg [4:0] character_index;
    reg sending;
    (* ASYNC_REG = "TRUE" *) reg [1:0] button_sync;
    reg button_stable_n;
    reg [31:0] button_debounce_counter;

    assign calibration_reference_vpp_uv = 24'd200000;
    assign rounded_vpp0_uv = {component0_amplitude_uv, 1'b0}+25'd500;
    assign rounded_vpp1_uv = {component1_amplitude_uv, 1'b0}+25'd500;

    g_uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) screen_uart_rx (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx), .data(rx_data),
        .valid(rx_valid), .framing_error(rx_framing_error)
    );

    g_uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) screen_uart_tx (
        .clk(clk), .rst_n(rst_n), .start(tx_start), .data(tx_data),
        .tx(uart_tx), .busy(tx_busy), .done(tx_done)
    );

    g_binary_to_bcd vpp0_bcd (
        .clk(clk), .rst_n(rst_n), .start(bcd_start),
        .binary(rounded_vpp0_uv), .busy(), .valid(bcd0_valid), .bcd(bcd0)
    );
    g_binary_to_bcd frequency0_bcd (
        .clk(clk), .rst_n(rst_n), .start(bcd_start),
        .binary({5'd0, component0_frequency_hz}),
        .busy(), .valid(bcd2_valid), .bcd(bcd2)
    );
    g_binary_to_bcd vpp1_bcd (
        .clk(clk), .rst_n(rst_n), .start(bcd_start),
        .binary(rounded_vpp1_uv), .busy(), .valid(bcd3_valid), .bcd(bcd3)
    );
    g_binary_to_bcd frequency1_bcd (
        .clk(clk), .rst_n(rst_n), .start(bcd_start),
        .binary({5'd0, component1_frequency_hz}),
        .busy(), .valid(bcd4_valid), .bcd(bcd4)
    );

    function [7:0] selected_digit;
        input [2:0] selected_field;
        input [2:0] digit;
        reg [31:0] selected_bcd;
        reg [3:0] nibble;
        begin
            case (selected_field)
                0: selected_bcd = bcd_x0;
                1: selected_bcd = bcd_x2;
                2: selected_bcd = bcd_x3;
                default: selected_bcd = bcd_x4;
            endcase
            if (selected_field == 0 || selected_field == 2) begin
                // BCD is rounded Vpp in uV. Dropping three decimal digits
                // gives integer mV. Prefix one zero to make six digits.
                case (digit)
                    0: nibble = 4'd0;
                    1: nibble = selected_bcd[31:28];
                    2: nibble = selected_bcd[27:24];
                    3: nibble = selected_bcd[23:20];
                    4: nibble = selected_bcd[19:16];
                    default: nibble = selected_bcd[15:12];
                endcase
            end else begin
                case (digit)
                    0: nibble = selected_bcd[23:20];
                    1: nibble = selected_bcd[19:16];
                    2: nibble = selected_bcd[15:12];
                    3: nibble = selected_bcd[11:8];
                    4: nibble = selected_bcd[7:4];
                    default: nibble = selected_bcd[3:0];
                endcase
            end
            selected_digit = 8'h30+{4'd0, nibble};
        end
    endfunction

    function [2:0] first_digit;
        input [2:0] selected_field;
        begin
            if (selected_digit(selected_field, 0) != "0")
                first_digit = 0;
            else if (selected_digit(selected_field, 1) != "0")
                first_digit = 1;
            else if (selected_digit(selected_field, 2) != "0")
                first_digit = 2;
            else if (selected_digit(selected_field, 3) != "0")
                first_digit = 3;
            else if (selected_digit(selected_field, 4) != "0")
                first_digit = 4;
            else
                first_digit = 5;
        end
    endfunction

    function [7:0] command_character;
        input [2:0] selected_field;
        input [4:0] character;
        reg [7:0] object_digit;
        begin
            case (selected_field)
                0: object_digit = "0";
                1: object_digit = "2";
                2: object_digit = "3";
                default: object_digit = "4";
            endcase
            case (character)
                0: command_character = "x";
                1: command_character = object_digit;
                2: command_character = ".";
                3: command_character = "v";
                4: command_character = "a";
                5: command_character = "l";
                6: command_character = "=";
                7: command_character = selected_digit(selected_field, 0);
                8: command_character = selected_digit(selected_field, 1);
                9: command_character = selected_digit(selected_field, 2);
                10: command_character = selected_digit(selected_field, 3);
                11: command_character = selected_digit(selected_field, 4);
                12: command_character = selected_digit(selected_field, 5);
                default: command_character = 8'hff;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            calibrate_start <= 1'b0;
            rx_calibrate_command <= 1'b0;
            rx_framing_error_sticky <= 1'b0;
        end else begin
            calibrate_start <= 1'b0;
            rx_calibrate_command <= 1'b0;
            if (rx_framing_error)
                rx_framing_error_sticky <= 1'b1;
            if (rx_valid && rx_data == 8'h43) begin
                calibrate_start <= 1'b1;
                rx_calibrate_command <= 1'b1;
            end
        end
    end

    // KEY1/R19 is pulled high and shorts to ground when pressed. The board
    // already has an RC network; this digital filter still requires 20 ms of
    // continuous disagreement before accepting either edge.
    always @(posedge clk) begin
        if (!rst_n) begin
            button_sync <= 2'b11;
            button_stable_n <= 1'b1;
            button_debounce_counter <= 32'd0;
            send_button_pressed <= 1'b0;
        end else begin
            button_sync <= {button_sync[0], send_button_n};
            send_button_pressed <= 1'b0;
            if (button_sync[1] == button_stable_n) begin
                button_debounce_counter <= 32'd0;
            end else if (button_debounce_counter == DEBOUNCE_CYCLES-1) begin
                button_debounce_counter <= 32'd0;
                button_stable_n <= button_sync[1];
                if (button_stable_n && !button_sync[1])
                    send_button_pressed <= 1'b1;
            end else begin
                button_debounce_counter <= button_debounce_counter+1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            bcd_start <= 1'b0;
            have_snapshot <= 1'b0;
            bcd_x0 <= 32'd0;
            bcd_x2 <= 32'd0;
            bcd_x3 <= 32'd0;
            bcd_x4 <= 32'd0;
            transmitted_component_count <= 2'd0;
            transmitted_fundamental_frequency_hz <= 20'd0;
            transmitted_harmonic_frequency_hz <= 20'd0;
            transmitted_fundamental_amplitude_uv <= 24'd0;
            transmitted_harmonic_amplitude_uv <= 24'd0;
        end else begin
            bcd_start <= 1'b0;
            if (measurement_valid) begin
                bcd_start <= 1'b1;
                transmitted_component_count <= component_count;
                transmitted_fundamental_frequency_hz <=
                    component0_frequency_hz;
                transmitted_harmonic_frequency_hz <=
                    (component_count >= 2) ? component1_frequency_hz : 20'd0;
                transmitted_fundamental_amplitude_uv <=
                    component0_amplitude_uv;
                transmitted_harmonic_amplitude_uv <=
                    (component_count >= 2) ? component1_amplitude_uv : 24'd0;
            end
            if (bcd0_valid && bcd2_valid && bcd3_valid && bcd4_valid) begin
                bcd_x0 <= bcd0;
                bcd_x2 <= bcd2;
                bcd_x3 <= (transmitted_component_count >= 2) ? bcd3 : 32'd0;
                bcd_x4 <= (transmitted_component_count >= 2) ? bcd4 : 32'd0;
                have_snapshot <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            field_index <= 3'd0;
            digit_start <= 3'd0;
            character_index <= 5'd0;
            sending <= 1'b0;
            tx_start <= 1'b0;
            tx_data <= 8'hff;
        end else begin
            tx_start <= 1'b0;
            if (!sending) begin
                if (send_button_pressed && have_snapshot) begin
                    field_index <= 3'd0;
                    digit_start <= first_digit(3'd0);
                    character_index <= 5'd0;
                    sending <= 1'b1;
                end
            end else if (!tx_busy && !tx_start) begin
                tx_data <= command_character(field_index, character_index);
                tx_start <= 1'b1;
                if (character_index == 5'd15) begin
                    character_index <= 5'd0;
                    if (field_index == 3'd3) begin
                        sending <= 1'b0;
                    end else begin
                        field_index <= field_index+1'b1;
                        digit_start <= first_digit(field_index+1'b1);
                    end
                end else if (character_index == 5'd6) begin
                    character_index <= 5'd7+digit_start;
                end else begin
                    character_index <= character_index+1'b1;
                end
            end
        end
    end

endmodule
