`timescale 1ns/1ps

// TJC8048X270_11 measurement-page adapter, 115200/8-N-1.
//
// Screen release-event bytes:
//   43 ('C') = calibrate with a 100 kHz / 200 mVpp single tone
//   31 ('1') = waveform, one complete fundamental period
//   33 ('3') = waveform, three complete fundamental periods
//   53 ('S') = positive-frequency spectrum
//
// R19 sends x0..x7 followed by the currently selected 800-point s0 image.
// Plot-only touch requests redraw s0 immediately.  addt uses the documented
// FE-ready / FD-finished transparent-mode handshake.
module g_tjc_display_uart #(
    parameter integer CLK_HZ = 200000000,
    parameter integer BAUD = 115200,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer DISPLAY_POINTS = 800,
    parameter integer HANDSHAKE_TIMEOUT_MS = 100
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,
    output wire        uart_tx,
    input  wire        send_button_n,

    input  wire        measurement_valid,
    input  wire [1:0]  component_count,
    input  wire [23:0] total_vpp_uv,
    input  wire [23:0] total_true_rms_uv,
    input  wire [19:0] component0_frequency_hz,
    input  wire [19:0] component1_frequency_hz,
    input  wire [19:0] component2_frequency_hz,
    input  wire [23:0] component0_amplitude_uv,
    input  wire [23:0] component1_amplitude_uv,
    input  wire [23:0] component2_amplitude_uv,

    input  wire        waveform_display_ready,
    input  wire        waveform_render_busy,
    input  wire        waveform_render_done,
    input  wire [7:0]  waveform_display_data,
    input  wire        spectrum_display_ready,
    input  wire [7:0]  spectrum_display_data,
    output reg  [9:0]  display_read_addr,
    output reg         waveform_render_request,
    output reg         three_cycle_mode,
    output reg         spectrum_mode,

    output reg         calibrate_start,
    output wire [23:0] calibration_reference_vpp_uv,
    output reg         rx_calibrate_command,
    output reg         rx_framing_error_sticky,
    output reg         send_button_pressed,
    output wire        tx_busy,
    output reg         transfer_busy,
    output reg         transfer_done,
    output reg         transparent_timeout_sticky,
    output reg         request_overrun
);

    localparam integer DEBOUNCE_CYCLES =
        (CLK_HZ/1000)*DEBOUNCE_MS;
    localparam integer HANDSHAKE_TIMEOUT_CYCLES =
        (CLK_HZ/1000)*HANDSHAKE_TIMEOUT_MS;
    localparam [3:0] TX_IDLE = 4'd0;
    localparam [3:0] TX_COPY_PLOT = 4'd1;
    localparam [3:0] TX_NUMERIC = 4'd2;
    localparam [3:0] TX_ADDT = 4'd3;
    localparam [3:0] TX_WAIT_FE = 4'd4;
    localparam [3:0] TX_RAW = 4'd5;
    localparam [3:0] TX_WAIT_FD = 4'd6;
    localparam [3:0] TX_CLEAR = 4'd7;
    localparam [3:0] TX_COPY_WAIT = 4'd8;

    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_framing_error;
    reg tx_start;
    reg [7:0] tx_data;
    wire tx_done;

    reg bcd_start;
    wire bcd0_valid;
    wire bcd1_valid;
    wire bcd2_valid;
    wire bcd3_valid;
    wire bcd4_valid;
    wire bcd5_valid;
    wire bcd6_valid;
    wire bcd7_valid;
    wire [31:0] bcd0;
    wire [31:0] bcd1;
    wire [31:0] bcd2;
    wire [31:0] bcd3;
    wire [31:0] bcd4;
    wire [31:0] bcd5;
    wire [31:0] bcd6;
    wire [31:0] bcd7;
    reg [31:0] bcd_x0;
    reg [31:0] bcd_x1;
    reg [31:0] bcd_x2;
    reg [31:0] bcd_x3;
    reg [31:0] bcd_x4;
    reg [31:0] bcd_x5;
    reg [31:0] bcd_x6;
    reg [31:0] bcd_x7;
    reg have_snapshot;

    (* ASYNC_REG = "TRUE" *) reg [1:0] button_sync;
    reg button_stable_n;
    reg [31:0] button_debounce_counter;

    reg full_request_pending;
    reg plot_request_pending;
    reg waveform_refresh_seen;
    reg selected_transfer_spectrum;
    reg selected_transfer_full;
    (* ram_style = "block" *) reg [7:0] plot_snapshot [0:DISPLAY_POINTS-1];
    reg [7:0] plot_snapshot_read_data;
    reg [9:0] copy_index;
    reg [9:0] raw_index;
    reg [3:0] tx_state;
    reg [3:0] numeric_field;
    reg [4:0] command_index;
    reg [3:0] digit_start;
    reg [31:0] handshake_counter;
    reg [31:0] request_wait_counter;

    wire selected_display_ready;
    wire all_bcd_valid;
    wire [3:0] selected_last_digit;
    wire [3:0] selected_digit_count;
    wire [4:0] numeric_final_index;

    assign calibration_reference_vpp_uv = 24'd200000;
    assign selected_display_ready = spectrum_mode ?
        spectrum_display_ready : waveform_display_ready;
    assign all_bcd_valid = bcd0_valid && bcd1_valid && bcd2_valid &&
        bcd3_valid && bcd4_valid && bcd5_valid && bcd6_valid && bcd7_valid;
    // Frequency fields retain integer hertz and use three TJC decimal places,
    // so 500000 displays as 500.000 kHz.  Voltage fields are rounded from
    // microvolts to 10 uV units and use two decimal places, so 24680 displays
    // as 246.80 mV.
    assign selected_last_digit = (numeric_field == 4'd3 ||
        numeric_field == 4'd5 || numeric_field == 4'd7) ? 4'd7 : 4'd6;
    assign selected_digit_count = selected_last_digit-digit_start+1'b1;
    assign numeric_final_index = 5'd7+selected_digit_count+5'd2;

    g_uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) screen_uart_rx (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx), .data(rx_data),
        .valid(rx_valid), .framing_error(rx_framing_error)
    );
    g_uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) screen_uart_tx (
        .clk(clk), .rst_n(rst_n), .start(tx_start), .data(tx_data),
        .tx(uart_tx), .busy(tx_busy), .done(tx_done)
    );

    g_binary_to_bcd vpp_bcd (
        .clk(clk), .rst_n(rst_n), .start(bcd_start),
        .binary({1'b0, total_vpp_uv}+25'd5), .busy(),
        .valid(bcd0_valid), .bcd(bcd0));
    g_binary_to_bcd rms_bcd (
        .clk(clk), .rst_n(rst_n), .start(bcd_start),
        .binary({1'b0, total_true_rms_uv}+25'd5), .busy(),
        .valid(bcd1_valid), .bcd(bcd1));
    g_binary_to_bcd amplitude0_bcd (
        .clk(clk), .rst_n(rst_n), .start(bcd_start),
        .binary({1'b0, component0_amplitude_uv}+25'd5), .busy(),
        .valid(bcd2_valid), .bcd(bcd2));
    g_binary_to_bcd frequency0_bcd (
        .clk(clk), .rst_n(rst_n), .start(bcd_start),
        .binary({5'd0, component0_frequency_hz}), .busy(),
        .valid(bcd3_valid), .bcd(bcd3));
    g_binary_to_bcd amplitude1_bcd (
        .clk(clk), .rst_n(rst_n), .start(bcd_start),
        .binary({1'b0, component1_amplitude_uv}+25'd5), .busy(),
        .valid(bcd4_valid), .bcd(bcd4));
    g_binary_to_bcd frequency1_bcd (
        .clk(clk), .rst_n(rst_n), .start(bcd_start),
        .binary({5'd0, component1_frequency_hz}), .busy(),
        .valid(bcd5_valid), .bcd(bcd5));
    g_binary_to_bcd amplitude2_bcd (
        .clk(clk), .rst_n(rst_n), .start(bcd_start),
        .binary({1'b0, component2_amplitude_uv}+25'd5), .busy(),
        .valid(bcd6_valid), .bcd(bcd6));
    g_binary_to_bcd frequency2_bcd (
        .clk(clk), .rst_n(rst_n), .start(bcd_start),
        .binary({5'd0, component2_frequency_hz}), .busy(),
        .valid(bcd7_valid), .bcd(bcd7));

    function [31:0] selected_bcd;
        input [3:0] field_number;
        begin
            case (field_number)
                0: selected_bcd = bcd_x0;
                1: selected_bcd = bcd_x1;
                2: selected_bcd = bcd_x2;
                3: selected_bcd = bcd_x3;
                4: selected_bcd = bcd_x4;
                5: selected_bcd = bcd_x5;
                6: selected_bcd = bcd_x6;
                default: selected_bcd = bcd_x7;
            endcase
        end
    endfunction

    function [7:0] decimal_digit;
        input [3:0] field_number;
        input [3:0] digit_number;
        reg [31:0] value;
        reg [3:0] nibble;
        begin
            value = selected_bcd(field_number);
            case (digit_number)
                0: nibble = value[31:28];
                1: nibble = value[27:24];
                2: nibble = value[23:20];
                3: nibble = value[19:16];
                4: nibble = value[15:12];
                5: nibble = value[11:8];
                6: nibble = value[7:4];
                default: nibble = value[3:0];
            endcase
            decimal_digit = 8'h30+{4'd0, nibble};
        end
    endfunction

    function [3:0] first_digit;
        input [3:0] field_number;
        reg [3:0] final_digit;
        begin
            final_digit = (field_number == 4'd3 || field_number == 4'd5 ||
                field_number == 4'd7) ? 4'd7 : 4'd6;
            if (decimal_digit(field_number, 0) != "0") first_digit = 0;
            else if (decimal_digit(field_number, 1) != "0") first_digit = 1;
            else if (decimal_digit(field_number, 2) != "0") first_digit = 2;
            else if (decimal_digit(field_number, 3) != "0") first_digit = 3;
            else if (decimal_digit(field_number, 4) != "0") first_digit = 4;
            else if (final_digit >= 5 && decimal_digit(field_number, 5) != "0") first_digit = 5;
            else if (final_digit >= 6 && decimal_digit(field_number, 6) != "0") first_digit = 6;
            else if (final_digit >= 7 && decimal_digit(field_number, 7) != "0") first_digit = 7;
            else first_digit = final_digit;
        end
    endfunction

    function [7:0] numeric_character;
        input [3:0] field_number;
        input [4:0] character_number;
        input [3:0] first_number;
        reg [3:0] final_number;
        reg [3:0] count;
        begin
            final_number = (field_number == 4'd3 || field_number == 4'd5 ||
                field_number == 4'd7) ? 4'd7 : 4'd6;
            count = final_number-first_number+1'b1;
            case (character_number)
                0: numeric_character = "x";
                1: numeric_character = "0"+field_number[2:0];
                2: numeric_character = ".";
                3: numeric_character = "v";
                4: numeric_character = "a";
                5: numeric_character = "l";
                6: numeric_character = "=";
                default: begin
                    if (character_number < 7+count)
                        numeric_character = decimal_digit(field_number,
                            first_number+character_number-7);
                    else
                        numeric_character = 8'hff;
                end
            endcase
        end
    endfunction

    function [7:0] addt_character;
        input [4:0] character_number;
        begin
            case (character_number)
                0: addt_character = "a";
                1: addt_character = "d";
                2: addt_character = "d";
                3: addt_character = "t";
                4: addt_character = " ";
                5: addt_character = "s";
                6: addt_character = "0";
                7: addt_character = ".";
                8: addt_character = "i";
                9: addt_character = "d";
                10: addt_character = ",";
                11: addt_character = "0";
                12: addt_character = ",";
                13: addt_character = "8";
                14: addt_character = "0";
                15: addt_character = "0";
                default: addt_character = 8'hff;
            endcase
        end
    endfunction

    function [7:0] clear_character;
        input [3:0] character_number;
        begin
            case (character_number)
                0: clear_character = "c";
                1: clear_character = "l";
                2: clear_character = "e";
                3: clear_character = " ";
                4: clear_character = "s";
                5: clear_character = "0";
                6: clear_character = ".";
                7: clear_character = "i";
                8: clear_character = "d";
                9: clear_character = ",";
                10: clear_character = "0";
                default: clear_character = 8'hff;
            endcase
        end
    endfunction

    // Screen command decode and protocol return detection.
    always @(posedge clk) begin
        if (!rst_n) begin
            calibrate_start <= 1'b0;
            rx_calibrate_command <= 1'b0;
            rx_framing_error_sticky <= 1'b0;
            waveform_render_request <= 1'b0;
            three_cycle_mode <= 1'b0;
            spectrum_mode <= 1'b0;
        end else begin
            calibrate_start <= 1'b0;
            rx_calibrate_command <= 1'b0;
            waveform_render_request <= 1'b0;
            if (rx_framing_error)
                rx_framing_error_sticky <= 1'b1;
            if (rx_valid) begin
                case (rx_data)
                    8'h43: begin
                        calibrate_start <= 1'b1;
                        rx_calibrate_command <= 1'b1;
                    end
                    8'h31: begin
                        three_cycle_mode <= 1'b0;
                        spectrum_mode <= 1'b0;
                        waveform_render_request <= 1'b1;
                    end
                    8'h33: begin
                        three_cycle_mode <= 1'b1;
                        spectrum_mode <= 1'b0;
                        waveform_render_request <= 1'b1;
                    end
                    8'h53: spectrum_mode <= 1'b1;
                    default: begin end
                endcase
            end
        end
    end

    // R19 is active low and requires a stable 20 ms state change.
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

    // Latch a coherent set of eight display fields.
    always @(posedge clk) begin
        if (!rst_n) begin
            bcd_start <= 1'b0;
            have_snapshot <= 1'b0;
            bcd_x0 <= 32'd0; bcd_x1 <= 32'd0;
            bcd_x2 <= 32'd0; bcd_x3 <= 32'd0;
            bcd_x4 <= 32'd0; bcd_x5 <= 32'd0;
            bcd_x6 <= 32'd0; bcd_x7 <= 32'd0;
        end else begin
            bcd_start <= 1'b0;
            if (measurement_valid)
                bcd_start <= 1'b1;
            if (all_bcd_valid) begin
                bcd_x0 <= bcd0;
                bcd_x1 <= bcd1;
                bcd_x2 <= bcd2;
                bcd_x3 <= bcd3;
                bcd_x4 <= (component_count >= 2) ? bcd4 : 32'd0;
                bcd_x5 <= (component_count >= 2) ? bcd5 : 32'd0;
                bcd_x6 <= (component_count >= 3) ? bcd6 : 32'd0;
                bcd_x7 <= (component_count >= 3) ? bcd7 : 32'd0;
                have_snapshot <= 1'b1;
            end
        end
    end

    // Transaction scheduler and transparent-mode sender.
    always @(posedge clk) begin
        if (!rst_n) begin
            full_request_pending <= 1'b0;
            plot_request_pending <= 1'b0;
            waveform_refresh_seen <= 1'b1;
            selected_transfer_spectrum <= 1'b0;
            selected_transfer_full <= 1'b0;
            copy_index <= 10'd0;
            raw_index <= 10'd0;
            tx_state <= TX_IDLE;
            numeric_field <= 4'd0;
            command_index <= 5'd0;
            digit_start <= 4'd0;
            handshake_counter <= 32'd0;
            request_wait_counter <= 32'd0;
            display_read_addr <= 10'd0;
            plot_snapshot_read_data <= 8'd0;
            tx_start <= 1'b0;
            tx_data <= 8'hff;
            transfer_busy <= 1'b0;
            transfer_done <= 1'b0;
            transparent_timeout_sticky <= 1'b0;
            request_overrun <= 1'b0;
        end else begin
            // Synchronous snapshot read permits a compact BRAM implementation.
            // UART byte spacing is much longer than this one-cycle latency.
            plot_snapshot_read_data <= plot_snapshot[raw_index];
            tx_start <= 1'b0;
            transfer_done <= 1'b0;

            if (send_button_pressed) begin
                if (full_request_pending)
                    request_overrun <= 1'b1;
                full_request_pending <= 1'b1;
            end
            if (rx_valid && (rx_data == 8'h31 || rx_data == 8'h33 ||
                    rx_data == 8'h53)) begin
                if (plot_request_pending)
                    request_overrun <= 1'b1;
                plot_request_pending <= 1'b1;
                if (rx_data == 8'h31 || rx_data == 8'h33)
                    waveform_refresh_seen <= 1'b0;
            end
            if (waveform_render_done)
                waveform_refresh_seen <= 1'b1;

            case (tx_state)
                TX_IDLE: begin
                    transfer_busy <= 1'b0;
                    handshake_counter <= 32'd0;
                    if (full_request_pending && have_snapshot &&
                            selected_display_ready &&
                            (spectrum_mode || !waveform_render_busy)) begin
                        selected_transfer_spectrum <= spectrum_mode;
                        selected_transfer_full <= 1'b1;
                        full_request_pending <= 1'b0;
                        copy_index <= 10'd0;
                        display_read_addr <= 10'd0;
                        transfer_busy <= 1'b1;
                        request_wait_counter <= 32'd0;
                        tx_state <= TX_COPY_WAIT;
                    end else if (plot_request_pending &&
                            selected_display_ready &&
                            (spectrum_mode || waveform_refresh_seen)) begin
                        selected_transfer_spectrum <= spectrum_mode;
                        selected_transfer_full <= 1'b0;
                        plot_request_pending <= 1'b0;
                        copy_index <= 10'd0;
                        display_read_addr <= 10'd0;
                        transfer_busy <= 1'b1;
                        request_wait_counter <= 32'd0;
                        tx_state <= TX_COPY_WAIT;
                    end else if (full_request_pending ||
                            plot_request_pending) begin
                        if (request_wait_counter >=
                                HANDSHAKE_TIMEOUT_CYCLES-1) begin
                            full_request_pending <= 1'b0;
                            plot_request_pending <= 1'b0;
                            request_wait_counter <= 32'd0;
                            transparent_timeout_sticky <= 1'b1;
                        end else begin
                            request_wait_counter <= request_wait_counter+1'b1;
                        end
                    end else begin
                        request_wait_counter <= 32'd0;
                    end
                end

                // Both display builders use synchronous BRAM reads.  The
                // address has been stable for a full clock when this state
                // advances to the capture state.
                TX_COPY_WAIT: begin
                    tx_state <= TX_COPY_PLOT;
                end

                TX_COPY_PLOT: begin
                    plot_snapshot[copy_index] <= selected_transfer_spectrum ?
                        spectrum_display_data : waveform_display_data;
                    if (copy_index == DISPLAY_POINTS-1) begin
                        if (selected_transfer_full) begin
                            numeric_field <= 4'd0;
                            digit_start <= first_digit(4'd0);
                            command_index <= 5'd0;
                            tx_state <= TX_NUMERIC;
                        end else begin
                            command_index <= 5'd0;
                            tx_state <= TX_CLEAR;
                        end
                    end else begin
                        copy_index <= copy_index+1'b1;
                        display_read_addr <= copy_index+1'b1;
                        tx_state <= TX_COPY_WAIT;
                    end
                end

                TX_NUMERIC: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= numeric_character(numeric_field,
                            command_index, digit_start);
                        tx_start <= 1'b1;
                        if (command_index == numeric_final_index) begin
                            command_index <= 5'd0;
                            if (numeric_field == 4'd7) begin
                                tx_state <= TX_CLEAR;
                            end else begin
                                numeric_field <= numeric_field+1'b1;
                                digit_start <= first_digit(numeric_field+1'b1);
                            end
                        end else begin
                            command_index <= command_index+1'b1;
                        end
                    end
                end

                TX_CLEAR: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= clear_character(command_index[3:0]);
                        tx_start <= 1'b1;
                        if (command_index == 5'd13) begin
                            command_index <= 5'd0;
                            tx_state <= TX_ADDT;
                        end else begin
                            command_index <= command_index+1'b1;
                        end
                    end
                end

                TX_ADDT: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= addt_character(command_index);
                        tx_start <= 1'b1;
                        if (command_index == 5'd18) begin
                            command_index <= 5'd0;
                            handshake_counter <= 32'd0;
                            tx_state <= TX_WAIT_FE;
                        end else begin
                            command_index <= command_index+1'b1;
                        end
                    end
                end

                TX_WAIT_FE: begin
                    if (rx_valid && rx_data == 8'hfe) begin
                        raw_index <= 10'd0;
                        handshake_counter <= 32'd0;
                        tx_state <= TX_RAW;
                    end else if (handshake_counter >=
                            HANDSHAKE_TIMEOUT_CYCLES-1) begin
                        transparent_timeout_sticky <= 1'b1;
                        transfer_busy <= 1'b0;
                        tx_state <= TX_IDLE;
                    end else begin
                        handshake_counter <= handshake_counter+1'b1;
                    end
                end

                TX_RAW: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data <= plot_snapshot_read_data;
                        tx_start <= 1'b1;
                        if (raw_index == DISPLAY_POINTS-1) begin
                            handshake_counter <= 32'd0;
                            tx_state <= TX_WAIT_FD;
                        end else begin
                            raw_index <= raw_index+1'b1;
                        end
                    end
                end

                TX_WAIT_FD: begin
                    if (rx_valid && rx_data == 8'hfd) begin
                        transfer_busy <= 1'b0;
                        transfer_done <= 1'b1;
                        tx_state <= TX_IDLE;
                    end else if (handshake_counter >=
                            HANDSHAKE_TIMEOUT_CYCLES-1) begin
                        transparent_timeout_sticky <= 1'b1;
                        transfer_busy <= 1'b0;
                        tx_state <= TX_IDLE;
                    end else begin
                        handshake_counter <= handshake_counter+1'b1;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

endmodule
