`timescale 1ns/1ps

// Build an 800-point qualitative waveform from the 20 MSPS post-FIR stream
// and measure the phase-dependent composite peak-to-peak voltage.  The ring
// buffer retains enough history for three 10 kHz periods (6000 samples).
module g_time_domain_display #(
    parameter integer SAMPLE_RATE_HZ = 20000000,
    parameter integer BUFFER_ADDR_WIDTH = 13,
    parameter integer DISPLAY_POINTS = 800
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_valid,
    input  wire signed [15:0] sample_data,

    input  wire               measurement_valid,
    input  wire [19:0]        fundamental_frequency_hz,
    input  wire [23:0]        active_gain_q16,
    input  wire               render_request,
    input  wire               render_three_cycles,

    input  wire [9:0]         display_read_addr,
    output wire [7:0]         display_read_data,
    output reg                display_ready,
    output reg                render_busy,
    output reg                render_done,
    output reg                request_overrun,
    output reg                total_vpp_valid,
    output reg  [15:0]        total_vpp_code,
    output reg  [23:0]        total_vpp_uv
);

    localparam integer BUFFER_DEPTH = (1 << BUFFER_ADDR_WIDTH);
    localparam [4:0] ST_IDLE = 5'd0;
    localparam [4:0] ST_PERIOD_START = 5'd1;
    localparam [4:0] ST_PERIOD_WAIT = 5'd2;
    localparam [4:0] ST_SCAN_READ = 5'd3;
    localparam [4:0] ST_SCAN_USE = 5'd4;
    localparam [4:0] ST_METRIC_MULT = 5'd5;
    localparam [4:0] ST_METRIC = 5'd6;
    localparam [4:0] ST_STEP_START = 5'd7;
    localparam [4:0] ST_STEP_WAIT = 5'd8;
    localparam [4:0] ST_RENDER_READ = 5'd9;
    localparam [4:0] ST_SCALE_START = 5'd10;
    localparam [4:0] ST_SCALE_PRODUCT = 5'd11;
    localparam [4:0] ST_SCALE_DIV_START = 5'd12;
    localparam [4:0] ST_SCALE_WAIT = 5'd13;
    localparam [4:0] ST_SCAN_FINALIZE = 5'd14;
    localparam [4:0] ST_RENDER_READ_NEXT = 5'd15;
    localparam [4:0] ST_INTERPOLATE_MULT = 5'd16;
    localparam [4:0] ST_INTERPOLATE_APPLY = 5'd17;
    localparam [4:0] ST_SCAN_READ_WAIT = 5'd18;
    localparam [4:0] ST_RENDER_READ_WAIT = 5'd19;
    localparam [4:0] ST_RENDER_NEXT_WAIT = 5'd20;
    localparam [4:0] ST_INTERPOLATE_DIFF = 5'd21;
    localparam [4:0] ST_SCAN_LATCH = 5'd22;

    (* ram_style = "block" *) reg signed [15:0] sample_memory [0:BUFFER_DEPTH-1];
    (* ram_style = "distributed" *) reg [7:0] display_memory [0:DISPLAY_POINTS-1];

    reg [BUFFER_ADDR_WIDTH-1:0] write_pointer;
    reg [BUFFER_ADDR_WIDTH:0] samples_available;
    reg [BUFFER_ADDR_WIDTH-1:0] ring_read_address;
    reg signed [15:0] ring_read_data;
    reg signed [15:0] scan_sample;
    reg [4:0] state;
    reg [BUFFER_ADDR_WIDTH-1:0] snapshot_pointer;
    reg [19:0] frequency_latched;
    reg [23:0] gain_latched;
    reg three_cycles_latched;
    reg [12:0] period_samples;
    reg [13:0] scan_samples;
    reg [13:0] scan_index;
    reg [BUFFER_ADDR_WIDTH-1:0] scan_start_address;
    reg signed [15:0] scan_minimum;
    reg signed [15:0] scan_maximum;
    reg [16:0] scan_range;
    reg [13:0] render_span;
    reg [BUFFER_ADDR_WIDTH-1:0] render_start_address;
    reg [31:0] render_phase_q16;
    reg [31:0] render_step_q16;
    reg [9:0] render_point;
    reg signed [15:0] interpolation_sample0;
    reg signed [15:0] interpolated_sample;
    reg signed [16:0] interpolation_difference;
    reg [15:0] interpolation_fraction;
    reg signed [33:0] interpolation_product;
    reg [16:0] sample_above_minimum;
    reg [24:0] scaled_sample_product;
    reg [40:0] metric_product;
    reg pending_render_request;
    reg pending_three_cycles;

    reg divider_start;
    reg [31:0] divider_numerator;
    reg [19:0] divider_denominator;
    wire divider_busy;
    wire divider_valid;
    wire divider_zero;
    wire [31:0] divider_quotient;

    wire signed [15:0] scan_minimum_next;
    wire signed [15:0] scan_maximum_next;
    wire [16:0] scan_range_next;
    wire [16:0] registered_scan_range;
    wire [40:0] rounded_metric_product;
    wire [24:0] metric_uv_shifted;

    assign display_read_data = (display_read_addr < DISPLAY_POINTS) ?
        display_memory[display_read_addr] : 8'd0;
    assign scan_minimum_next = (scan_sample < scan_minimum) ?
        scan_sample : scan_minimum;
    assign scan_maximum_next = (scan_sample > scan_maximum) ?
        scan_sample : scan_maximum;
    assign scan_range_next =
        $signed({scan_maximum_next[15], scan_maximum_next})-
        $signed({scan_minimum_next[15], scan_minimum_next});
    assign registered_scan_range =
        $signed({scan_maximum[15], scan_maximum})-
        $signed({scan_minimum[15], scan_minimum});
    assign rounded_metric_product = metric_product+41'd32768;
    assign metric_uv_shifted = rounded_metric_product >> 16;

    g_unsigned_divider #(
        .NUMERATOR_WIDTH(32), .DENOMINATOR_WIDTH(20)
    ) display_divider (
        .clk(clk), .rst_n(rst_n), .start(divider_start),
        .numerator(divider_numerator), .denominator(divider_denominator),
        .busy(divider_busy), .valid(divider_valid),
        .divide_by_zero(divider_zero), .quotient(divider_quotient)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            write_pointer <= {BUFFER_ADDR_WIDTH{1'b0}};
            samples_available <= {(BUFFER_ADDR_WIDTH+1){1'b0}};
        end else if (sample_valid) begin
            sample_memory[write_pointer] <= sample_data;
            write_pointer <= write_pointer+1'b1;
            if (!samples_available[BUFFER_ADDR_WIDTH])
                samples_available <= samples_available+1'b1;
        end
    end

    // A single registered read address keeps the 8192x16 ring buffer as a
    // true dual-port BRAM.  Multiple state-specific memory read expressions
    // caused Vivado to implement it as distributed RAM and created a long
    // address-adder/multiplexer path.
    always @(posedge clk) begin
        if (!rst_n)
            ring_read_data <= 16'sd0;
        else
            ring_read_data <= sample_memory[ring_read_address];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            snapshot_pointer <= {BUFFER_ADDR_WIDTH{1'b0}};
            frequency_latched <= 20'd0;
            gain_latched <= 24'd0;
            three_cycles_latched <= 1'b0;
            period_samples <= 13'd0;
            scan_samples <= 14'd0;
            scan_index <= 14'd0;
            scan_start_address <= {BUFFER_ADDR_WIDTH{1'b0}};
            ring_read_address <= {BUFFER_ADDR_WIDTH{1'b0}};
            scan_sample <= 16'sd0;
            scan_minimum <= 16'sh7fff;
            scan_maximum <= -16'sh8000;
            scan_range <= 17'd0;
            render_span <= 14'd0;
            render_start_address <= {BUFFER_ADDR_WIDTH{1'b0}};
            render_phase_q16 <= 32'd0;
            render_step_q16 <= 32'd0;
            render_point <= 10'd0;
            interpolation_sample0 <= 16'sd0;
            interpolated_sample <= 16'sd0;
            interpolation_difference <= 17'sd0;
            interpolation_fraction <= 16'd0;
            interpolation_product <= 34'sd0;
            sample_above_minimum <= 17'd0;
            scaled_sample_product <= 25'd0;
            metric_product <= 41'd0;
            pending_render_request <= 1'b0;
            pending_three_cycles <= 1'b0;
            divider_start <= 1'b0;
            divider_numerator <= 32'd0;
            divider_denominator <= 20'd1;
            display_ready <= 1'b0;
            render_busy <= 1'b0;
            render_done <= 1'b0;
            request_overrun <= 1'b0;
            total_vpp_valid <= 1'b0;
            total_vpp_code <= 16'd0;
            total_vpp_uv <= 24'd0;
        end else begin
            divider_start <= 1'b0;
            render_done <= 1'b0;
            total_vpp_valid <= 1'b0;

            // Keep every request until ST_IDLE can accept it.  The previous
            // one-cycle pulse handling lost a request when ST_IDLE was waiting
            // for a valid frequency or a full ring buffer, leaving the UART
            // transaction waiting indefinitely for render_done.
            if (render_request) begin
                if (pending_render_request)
                    request_overrun <= 1'b1;
                pending_render_request <= 1'b1;
                pending_three_cycles <= render_three_cycles;
            end

            case (state)
                ST_IDLE: begin
                    render_busy <= 1'b0;
                    if ((measurement_valid || render_request ||
                            pending_render_request) &&
                            fundamental_frequency_hz >= 20'd10000 &&
                            fundamental_frequency_hz <= 20'd500000 &&
                            samples_available[BUFFER_ADDR_WIDTH]) begin
                        snapshot_pointer <= write_pointer;
                        frequency_latched <= fundamental_frequency_hz;
                        gain_latched <= active_gain_q16;
                        three_cycles_latched <= pending_render_request ?
                            pending_three_cycles : render_three_cycles;
                        pending_render_request <= 1'b0;
                        render_busy <= 1'b1;
                        state <= ST_PERIOD_START;
                    end
                end

                ST_PERIOD_START: begin
                    divider_numerator <= SAMPLE_RATE_HZ+
                        {12'd0, frequency_latched[19:1]};
                    divider_denominator <= frequency_latched;
                    divider_start <= 1'b1;
                    state <= ST_PERIOD_WAIT;
                end

                ST_PERIOD_WAIT: begin
                    if (divider_valid) begin
                        if (divider_zero || divider_quotient < 32'd40)
                            period_samples <= 13'd40;
                        else if (divider_quotient > 32'd2000)
                            period_samples <= 13'd2000;
                        else
                            period_samples <= divider_quotient[12:0];

                        if (divider_zero || divider_quotient < 32'd40)
                            scan_samples <= 14'd120;
                        else if (divider_quotient > 32'd2000)
                            scan_samples <= 14'd6000;
                        else
                            scan_samples <= divider_quotient[12:0]*3;

                        if (divider_zero || divider_quotient < 32'd40)
                            scan_start_address <= snapshot_pointer-13'd120;
                        else if (divider_quotient > 32'd2000)
                            scan_start_address <= snapshot_pointer-13'd6000;
                        else
                            scan_start_address <= snapshot_pointer-
                                (divider_quotient[12:0]*3);
                        scan_index <= 14'd0;
                        scan_minimum <= 16'sh7fff;
                        scan_maximum <= -16'sh8000;
                        state <= ST_SCAN_READ;
                    end
                end

                ST_SCAN_READ: begin
                    ring_read_address <=
                        scan_start_address+
                        scan_index[BUFFER_ADDR_WIDTH-1:0];
                    state <= ST_SCAN_READ_WAIT;
                end

                ST_SCAN_READ_WAIT: begin
                    state <= ST_SCAN_LATCH;
                end

                ST_SCAN_LATCH: begin
                    scan_sample <= ring_read_data;
                    state <= ST_SCAN_USE;
                end

                ST_SCAN_USE: begin
                    scan_minimum <= scan_minimum_next;
                    scan_maximum <= scan_maximum_next;
                    if (scan_index == scan_samples-1'b1) begin
                        state <= ST_SCAN_FINALIZE;
                    end else begin
                        scan_index <= scan_index+1'b1;
                        state <= ST_SCAN_READ;
                    end
                end

                ST_SCAN_FINALIZE: begin
                    // Min/max are now registered; perform their subtraction
                    // without the BRAM output and two comparisons in this path.
                    scan_range <= registered_scan_range;
                    total_vpp_code <= registered_scan_range[16] ?
                        16'hffff : registered_scan_range[15:0];
                    state <= ST_METRIC_MULT;
                end

                ST_METRIC_MULT: begin
                    // Register the min/max subtraction before the multiply.
                    // This keeps the BRAM output, comparator/subtractor and
                    // voltage scaling from becoming one 200 MHz path.
                    metric_product <= scan_range*gain_latched;
                    state <= ST_METRIC;
                end

                ST_METRIC: begin
                    total_vpp_uv <= metric_uv_shifted[24] ?
                        24'hffffff : metric_uv_shifted[23:0];
                    total_vpp_valid <= 1'b1;
                    if (three_cycles_latched) begin
                        render_span <= period_samples*3;
                        render_start_address <= snapshot_pointer-
                            (period_samples*3);
                    end else begin
                        render_span <= period_samples;
                        render_start_address <= snapshot_pointer-period_samples;
                    end
                    state <= ST_STEP_START;
                end

                ST_STEP_START: begin
                    divider_numerator <= (render_span-1'b1) << 16;
                    divider_denominator <= DISPLAY_POINTS-1;
                    divider_start <= 1'b1;
                    state <= ST_STEP_WAIT;
                end

                ST_STEP_WAIT: begin
                    if (divider_valid) begin
                        render_step_q16 <= divider_quotient;
                        render_phase_q16 <= 32'd0;
                        render_point <= 10'd0;
                        state <= ST_RENDER_READ;
                    end
                end

                ST_RENDER_READ: begin
                    ring_read_address <=
                        render_start_address+
                        render_phase_q16[BUFFER_ADDR_WIDTH+15:16];
                    interpolation_fraction <=
                        (render_point == DISPLAY_POINTS-1) ?
                        16'd0 : render_phase_q16[15:0];
                    state <= ST_RENDER_READ_WAIT;
                end

                ST_RENDER_READ_WAIT: begin
                    state <= ST_RENDER_READ_NEXT;
                end

                // Two sequential BRAM reads obtain adjacent 20 MSPS samples.
                // The following multiply/apply stages perform display-only
                // linear interpolation without extending the 200 MHz path.
                ST_RENDER_READ_NEXT: begin
                    interpolation_sample0 <= ring_read_data;
                    ring_read_address <=
                        render_start_address+
                        render_phase_q16[BUFFER_ADDR_WIDTH+15:16]+1'b1;
                    state <= ST_RENDER_NEXT_WAIT;
                end

                ST_RENDER_NEXT_WAIT: begin
                    state <= ST_INTERPOLATE_DIFF;
                end

                ST_INTERPOLATE_DIFF: begin
                    interpolation_difference <=
                        $signed({ring_read_data[15], ring_read_data})-
                        $signed({interpolation_sample0[15],
                        interpolation_sample0});
                    state <= ST_INTERPOLATE_MULT;
                end

                ST_INTERPOLATE_MULT: begin
                    interpolation_product <=
                        interpolation_difference*
                        $signed({1'b0, interpolation_fraction});
                    state <= ST_INTERPOLATE_APPLY;
                end

                ST_INTERPOLATE_APPLY: begin
                    interpolated_sample <=
                        $signed(interpolation_sample0)+
                        ($signed(interpolation_product) >>> 16);
                    state <= ST_SCALE_START;
                end

                ST_SCALE_START: begin
                    if (scan_range == 0) begin
                        display_memory[render_point] <= 8'd128;
                        if (render_point == DISPLAY_POINTS-1) begin
                            display_ready <= 1'b1;
                            render_busy <= 1'b0;
                            render_done <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            render_point <= render_point+1'b1;
                            render_phase_q16 <= render_phase_q16+
                                render_step_q16;
                            state <= ST_RENDER_READ;
                        end
                    end else begin
                        sample_above_minimum <=
                            $signed({interpolated_sample[15],
                            interpolated_sample})-
                            $signed({scan_minimum[15], scan_minimum});
                        state <= ST_SCALE_PRODUCT;
                    end
                end

                ST_SCALE_PRODUCT: begin
                    // 255*x = 256*x-x.  The two explicit pipeline stages
                    // replace the former BRAM-to-32-bit-divider 17-level path.
                    scaled_sample_product <=
                        {sample_above_minimum, 8'b0}-
                        {8'd0, sample_above_minimum};
                    state <= ST_SCALE_DIV_START;
                end

                ST_SCALE_DIV_START: begin
                    divider_numerator <= {7'd0, scaled_sample_product}+
                        {15'd0, scan_range[16:1]};
                    divider_denominator <= {3'd0, scan_range};
                    divider_start <= 1'b1;
                    state <= ST_SCALE_WAIT;
                end

                ST_SCALE_WAIT: begin
                    if (divider_valid) begin
                        display_memory[render_point] <=
                            (divider_quotient > 255) ? 8'hff :
                            divider_quotient[7:0];
                        if (render_point == DISPLAY_POINTS-1) begin
                            display_ready <= 1'b1;
                            render_busy <= 1'b0;
                            render_done <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            render_point <= render_point+1'b1;
                            render_phase_q16 <= render_phase_q16+
                                render_step_q16;
                            state <= ST_RENDER_READ;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
