`timescale 1ns/1ps

// Convert the positive 0..500 kHz half-spectrum (FFT bins 0..1024) into
// 800 qualitative amplitude points for the TJC waveform widget.  Adjacent
// FFT bins mapping to one display column are max-pooled, square-rooted and
// normalized to the strongest column so line heights remain proportional to
// voltage amplitude rather than power.
module g_spectrum_display #(
    parameter integer DISPLAY_POINTS = 800,
    parameter integer HORIZONTAL_MARGIN = 24
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        spectrum_valid,
    input  wire [11:0] spectrum_bin,
    input  wire [32:0] spectrum_power,
    input  wire [9:0]  display_read_addr,
    output wire [7:0]  display_read_data,
    output reg         display_ready,
    output reg         frame_done,
    output reg         processing_busy,
    output reg         capture_overrun
);

    localparam [3:0] ST_IDLE = 4'd0;
    localparam [3:0] ST_MAX_SQRT_START = 4'd1;
    localparam [3:0] ST_MAX_SQRT_WAIT = 4'd2;
    localparam [3:0] ST_POINT_READ = 4'd3;
    localparam [3:0] ST_POINT_SQRT_START = 4'd4;
    localparam [3:0] ST_POINT_SQRT_WAIT = 4'd5;
    localparam [3:0] ST_DIV_START = 4'd6;
    localparam [3:0] ST_DIV_WAIT = 4'd7;
    localparam integer ACTIVE_POINTS =
        DISPLAY_POINTS-(2*HORIZONTAL_MARGIN);
    localparam integer ACTIVE_SPAN = ACTIVE_POINTS-1;

    (* ram_style = "block" *) reg [32:0] power_memory [0:DISPLAY_POINTS-1];
    (* ram_style = "distributed" *) reg [7:0] display_memory [0:DISPLAY_POINTS-1];

    reg capture_active;
    reg mapping_valid_pipe;
    reg [11:0] mapping_bin_pipe;
    reg [32:0] mapping_power_pipe;
    reg [21:0] mapped_product_pipe;
    reg spectrum_valid_pipe;
    reg [11:0] spectrum_bin_pipe;
    reg [32:0] spectrum_power_pipe;
    reg [9:0] mapped_point_pipe;
    reg [9:0] capture_point;
    reg [32:0] capture_maximum;
    reg [32:0] frame_maximum;
    reg capture_complete;
    reg capture_flush_pending;

    reg [3:0] state;
    reg [9:0] process_point;
    reg [32:0] point_power;
    reg [16:0] maximum_magnitude;
    reg [16:0] point_magnitude;
    reg sqrt_start;
    wire sqrt_busy;
    wire sqrt_valid;
    wire [16:0] sqrt_root;
    reg divider_start;
    wire divider_busy;
    wire divider_valid;
    wire divider_zero;
    wire [23:0] divider_quotient;
    reg [23:0] divider_numerator;

    wire [10:0] mapped_unclamped;
    wire [9:0] mapped_point;
    wire [32:0] capture_power_next;
    wire [32:0] frame_maximum_next;

    assign display_read_data = (display_read_addr < DISPLAY_POINTS) ?
        display_memory[display_read_addr] : 8'd0;
    // Map bin 0 and bin 1024 inside the plot instead of onto the waveform
    // widget borders, where a vertical peak is visually clipped in half.
    assign mapped_unclamped = mapped_product_pipe >> 10;
    assign mapped_point = (mapped_unclamped >= ACTIVE_POINTS) ?
        DISPLAY_POINTS-HORIZONTAL_MARGIN-1 :
        mapped_unclamped[9:0]+HORIZONTAL_MARGIN;
    assign capture_power_next = (spectrum_power_pipe > capture_maximum) ?
        spectrum_power_pipe : capture_maximum;
    assign frame_maximum_next = (capture_power_next > frame_maximum) ?
        capture_power_next : frame_maximum;

    initial begin
        if (HORIZONTAL_MARGIN < 1 ||
                2*HORIZONTAL_MARGIN >= DISPLAY_POINTS)
            $error("HORIZONTAL_MARGIN must leave a non-empty active plot");
    end

    g_integer_sqrt magnitude_sqrt (
        .clk(clk), .rst_n(rst_n), .start(sqrt_start),
        .radicand((state == ST_MAX_SQRT_WAIT ||
            state == ST_MAX_SQRT_START) ? frame_maximum : point_power),
        .busy(sqrt_busy), .valid(sqrt_valid), .root(sqrt_root)
    );

    g_unsigned_divider #(
        .NUMERATOR_WIDTH(24), .DENOMINATOR_WIDTH(17)
    ) level_divider (
        .clk(clk), .rst_n(rst_n), .start(divider_start),
        .numerator(divider_numerator), .denominator(maximum_magnitude),
        .busy(divider_busy), .valid(divider_valid),
        .divide_by_zero(divider_zero), .quotient(divider_quotient)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            capture_active <= 1'b0;
            mapping_valid_pipe <= 1'b0;
            mapping_bin_pipe <= 12'd0;
            mapping_power_pipe <= 33'd0;
            mapped_product_pipe <= 22'd0;
            spectrum_valid_pipe <= 1'b0;
            spectrum_bin_pipe <= 12'd0;
            spectrum_power_pipe <= 33'd0;
            mapped_point_pipe <= 10'd0;
            capture_point <= 10'd0;
            capture_maximum <= 33'd0;
            frame_maximum <= 33'd0;
            capture_complete <= 1'b0;
            capture_flush_pending <= 1'b0;
            state <= ST_IDLE;
            process_point <= 10'd0;
            point_power <= 33'd0;
            maximum_magnitude <= 17'd0;
            point_magnitude <= 17'd0;
            sqrt_start <= 1'b0;
            divider_start <= 1'b0;
            divider_numerator <= 24'd0;
            display_ready <= 1'b0;
            frame_done <= 1'b0;

            processing_busy <= 1'b0;
            capture_overrun <= 1'b0;
        end else begin
            capture_complete <= 1'b0;
            sqrt_start <= 1'b0;
            divider_start <= 1'b0;
            frame_done <= 1'b0;

            // Split constant multiplication and margin/clamp into two stages.
            // This keeps the DSP and following LUT arithmetic out of one
            // 5 ns path while preserving bin/power alignment.
            mapping_valid_pipe <= spectrum_valid &&
                spectrum_bin <= 12'd1024;
            if (spectrum_valid && spectrum_bin <= 12'd1024) begin
                mapping_bin_pipe <= spectrum_bin;
                mapping_power_pipe <= spectrum_power;
                mapped_product_pipe <= spectrum_bin*ACTIVE_SPAN;
            end

            spectrum_valid_pipe <= mapping_valid_pipe;
            if (mapping_valid_pipe) begin
                spectrum_bin_pipe <= mapping_bin_pipe;
                spectrum_power_pipe <= mapping_power_pipe;
                mapped_point_pipe <= mapped_point;
            end

            // Flush the final accumulated column on its own clock.  Keeping
            // every power_memory cycle to at most one write port is essential
            // for Vivado to infer BRAM instead of expanding 800x33 bits into
            // flip-flops and a very large read multiplexer.
            if (capture_flush_pending) begin
                power_memory[capture_point] <= capture_maximum;
                if (capture_maximum > frame_maximum)
                    frame_maximum <= capture_maximum;
                capture_flush_pending <= 1'b0;
                capture_complete <= 1'b1;
            end else if (spectrum_valid_pipe) begin
                if (spectrum_bin_pipe == 0) begin
                    if (processing_busy)
                        capture_overrun <= 1'b1;
                    capture_active <= 1'b1;
                    capture_point <= 10'd0;
                    capture_maximum <= spectrum_power_pipe;
                    frame_maximum <= 33'd0;
                end else if (capture_active) begin
                    if (mapped_point_pipe == capture_point) begin
                        capture_maximum <= capture_power_next;
                    end else begin
                        power_memory[capture_point] <= capture_maximum;
                        if (capture_maximum > frame_maximum)
                            frame_maximum <= capture_maximum;
                        capture_point <= mapped_point_pipe;
                        capture_maximum <= spectrum_power_pipe;
                    end

                    if (spectrum_bin_pipe == 12'd1024) begin
                        capture_active <= 1'b0;
                        capture_flush_pending <= 1'b1;
                    end
                end
            end

            case (state)
                ST_IDLE: begin
                    processing_busy <= 1'b0;
                    if (capture_complete) begin
                        processing_busy <= 1'b1;
                        state <= ST_MAX_SQRT_START;
                    end
                end

                ST_MAX_SQRT_START: begin
                    sqrt_start <= 1'b1;
                    state <= ST_MAX_SQRT_WAIT;
                end

                ST_MAX_SQRT_WAIT: begin
                    if (sqrt_valid) begin
                        maximum_magnitude <= sqrt_root;
                        process_point <= 10'd0;
                        state <= ST_POINT_READ;
                    end
                end

                ST_POINT_READ: begin
                    point_power <= power_memory[process_point];
                    state <= ST_POINT_SQRT_START;
                end

                ST_POINT_SQRT_START: begin
                    if (process_point < HORIZONTAL_MARGIN ||
                            process_point >=
                            DISPLAY_POINTS-HORIZONTAL_MARGIN) begin
                        display_memory[process_point] <= 8'd0;
                        if (process_point == DISPLAY_POINTS-1) begin
                            display_ready <= 1'b1;
                            frame_done <= 1'b1;
                            processing_busy <= 1'b0;
                            state <= ST_IDLE;
                        end else begin
                            process_point <= process_point+1'b1;
                            state <= ST_POINT_READ;
                        end
                    end else if (maximum_magnitude == 0) begin
                        display_memory[process_point] <= 8'd0;
                        if (process_point == DISPLAY_POINTS-1) begin
                            display_ready <= 1'b1;
                            frame_done <= 1'b1;
                            processing_busy <= 1'b0;
                            state <= ST_IDLE;
                        end else begin
                            process_point <= process_point+1'b1;
                            state <= ST_POINT_READ;
                        end
                    end else begin
                        sqrt_start <= 1'b1;
                        state <= ST_POINT_SQRT_WAIT;
                    end
                end

                ST_POINT_SQRT_WAIT: begin
                    if (sqrt_valid) begin
                        point_magnitude <= sqrt_root;
                        state <= ST_DIV_START;
                    end
                end

                ST_DIV_START: begin
                    divider_numerator <= point_magnitude*255+
                        {7'd0, maximum_magnitude[16:1]};
                    divider_start <= 1'b1;
                    state <= ST_DIV_WAIT;
                end

                ST_DIV_WAIT: begin
                    if (divider_valid) begin
                        display_memory[process_point] <=
                            (divider_zero || divider_quotient > 255) ?
                            8'hff : divider_quotient[7:0];
                        if (process_point == DISPLAY_POINTS-1) begin
                            display_ready <= 1'b1;
                            frame_done <= 1'b1;
                            processing_busy <= 1'b0;
                            state <= ST_IDLE;
                        end else begin
                            process_point <= process_point+1'b1;
                            state <= ST_POINT_READ;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
