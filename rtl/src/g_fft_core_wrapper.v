`timescale 1ns/1ps

// AXI4-Stream adapter for the Vivado 2020.2 xfft v9.1 core. The generated IP
// is fixed at 4096 points, natural-order output and block-floating scaling.
module g_fft_core_wrapper (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               input_valid,
    output wire               input_ready,
    input  wire signed [15:0] input_real,
    input  wire signed [15:0] input_imag,
    input  wire               input_last,

    output wire               output_valid,
    input  wire               output_ready,
    output wire signed [15:0] output_real,
    output wire signed [15:0] output_imag,
    output wire [11:0]        output_bin,
    output wire [4:0]         output_block_exponent,
    output wire               output_last,

    output wire               frame_started,
    output reg                configured,
    output reg  [4:0]         error_sticky
);

    wire [7:0] config_data;
    wire config_ready;
    wire [31:0] input_data;
    wire core_input_ready;
    wire [31:0] output_data;
    wire [23:0] output_user;
    wire [7:0] status_data;
    wire status_valid;
    wire event_tlast_unexpected;
    wire event_tlast_missing;
    wire event_status_channel_halt;
    wire event_data_in_channel_halt;
    wire event_data_out_channel_halt;

    // Fixed-length block-floating mode only needs FWD_INV in bit 0.
    assign config_data = 8'h01;
    assign input_data = {input_imag, input_real};
    assign input_ready = configured && core_input_ready;
    assign output_real = output_data[15:0];
    assign output_imag = output_data[31:16];
    // XK_INDEX occupies bits 11:0 and is padded to 16 bits. BLK_EXP follows.
    assign output_bin = output_user[11:0];
    assign output_block_exponent = output_user[20:16];

    always @(posedge clk) begin
        if (!rst_n) begin
            configured <= 1'b0;
            error_sticky <= 5'b00000;
        end else begin
            if (!configured && config_ready)
                configured <= 1'b1;
            if (event_tlast_unexpected)
                error_sticky[0] <= 1'b1;
            if (event_tlast_missing)
                error_sticky[1] <= 1'b1;
            if (event_status_channel_halt)
                error_sticky[2] <= 1'b1;
            if (event_data_in_channel_halt)
                error_sticky[3] <= 1'b1;
            if (event_data_out_channel_halt)
                error_sticky[4] <= 1'b1;
        end
    end

    g_fft_4096_ip fft_core (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_config_tdata(config_data),
        .s_axis_config_tvalid(!configured),
        .s_axis_config_tready(config_ready),
        .s_axis_data_tdata(input_data),
        .s_axis_data_tvalid(input_valid && configured),
        .s_axis_data_tready(core_input_ready),
        .s_axis_data_tlast(input_last),
        .m_axis_data_tdata(output_data),
        .m_axis_data_tuser(output_user),
        .m_axis_data_tvalid(output_valid),
        .m_axis_data_tready(output_ready),
        .m_axis_data_tlast(output_last),
        .m_axis_status_tdata(status_data),
        .m_axis_status_tvalid(status_valid),
        .m_axis_status_tready(1'b1),
        .event_frame_started(frame_started),
        .event_tlast_unexpected(event_tlast_unexpected),
        .event_tlast_missing(event_tlast_missing),
        .event_status_channel_halt(event_status_channel_halt),
        .event_data_in_channel_halt(event_data_in_channel_halt),
        .event_data_out_channel_halt(event_data_out_channel_halt)
    );

endmodule
