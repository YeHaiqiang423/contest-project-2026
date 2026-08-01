`timescale 1ns/1ps

// Phase estimator for the three strongest spectral components.
//
// The input samples are the same 4096-point Hann-windowed stream presented to
// the FFT.  For each reported component frequency this block performs an
// exact-frequency correlation referenced to the centre of the Hann window:
//
//   C = sum(x[n] * cos(2*pi*f*(n-2047.5)/Fs))
//   S = sum(x[n] * sin(2*pi*f*(n-2047.5)/Fs))
//   phase = atan2(C, S)                         (sine-phase convention)
//
// Harmonic phase is reported as wrap(phi_h-order*phi_1).  Therefore an
// arbitrary frame start, pure delay and the linear phase of the FIR cancel.
module g_phase_estimator #(
    parameter integer SAMPLE_RATE_HZ = 2000000,
    parameter integer FRAME_LENGTH = 4096,
    parameter integer ADDR_WIDTH = 12,
    parameter SINE_FILE = "matlab/vectors/g_sine_q15_4096.hex"
) (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               fft_valid,
    input  wire               fft_ready,
    input  wire signed [15:0] fft_real,
    input  wire               fft_last,

    input  wire               spectrum_results_valid,
    input  wire [1:0]         component_count,
    input  wire [19:0]        peak0_frequency_hz,
    input  wire [19:0]        peak1_frequency_hz,
    input  wire [19:0]        peak2_frequency_hz,

    output reg                phase_results_valid,
    output reg                harmonic1_phase_valid,
    output reg                harmonic2_phase_valid,
    output reg  [8:0]         harmonic1_phase_deg,
    output reg  [8:0]         harmonic2_phase_deg,
    output wire               busy,
    output wire [2:0]         error_sticky
);

    localparam [5:0] ST_IDLE             = 6'd0;
    localparam [5:0] ST_SORT_01          = 6'd1;
    localparam [5:0] ST_SORT_12          = 6'd2;
    localparam [5:0] ST_SORT_01_AGAIN    = 6'd3;
    localparam [5:0] ST_CHECK_COUNT      = 6'd4;
    localparam [5:0] ST_ORDER1_START     = 6'd5;
    localparam [5:0] ST_ORDER1_WAIT      = 6'd6;
    localparam [5:0] ST_ORDER1_CHECK     = 6'd7;
    localparam [5:0] ST_ORDER2_START     = 6'd8;
    localparam [5:0] ST_ORDER2_WAIT      = 6'd9;
    localparam [5:0] ST_ORDER2_CHECK     = 6'd10;
    localparam [5:0] ST_PHASE_INC_MUL    = 6'd11;
    localparam [5:0] ST_PHASE_INC_ROUND  = 6'd12;
    localparam [5:0] ST_PASS_PREP        = 6'd13;
    localparam [5:0] ST_PASS_ISSUE       = 6'd14;
    localparam [5:0] ST_PASS_WAIT        = 6'd15;
    localparam [5:0] ST_PASS_MULTIPLY    = 6'd16;
    localparam [5:0] ST_PASS_ACCUMULATE  = 6'd17;
    localparam [5:0] ST_CORDIC_START     = 6'd18;
    localparam [5:0] ST_CORDIC_WAIT      = 6'd19;
    localparam [5:0] ST_RELATIVE1        = 6'd20;
    localparam [5:0] ST_DEGREE1_MUL      = 6'd21;
    localparam [5:0] ST_DEGREE1_ROUND    = 6'd22;
    localparam [5:0] ST_RELATIVE2        = 6'd23;
    localparam [5:0] ST_DEGREE2_MUL      = 6'd24;
    localparam [5:0] ST_DEGREE2_ROUND    = 6'd25;
    localparam [5:0] ST_STABILIZE        = 6'd26;
    localparam [5:0] ST_STABILITY_DECIDE = 6'd27;
    localparam [5:0] ST_PUBLISH          = 6'd28;
    localparam [5:0] ST_PHASE_PRODUCT    = 6'd29;
    localparam [5:0] ST_STABILITY_WRAP   = 6'd30;
    localparam [5:0] ST_DEGREE1_ADD      = 6'd31;
    localparam [5:0] ST_DEGREE2_ADD      = 6'd32;

    localparam [19:0] UNUSED_FREQUENCY = 20'hfffff;

    reg [5:0] state;

    wire capture_fire;
    wire capture_write_enable;
    reg [ADDR_WIDTH-1:0] capture_addr;
    reg capture_dropping;
    reg captured_frame_complete;
    reg consume_frame;
    reg capture_length_error_sticky;
    reg result_without_frame_sticky;
    reg phase_overrun_sticky;

    reg ram_read_enable;
    reg [ADDR_WIDTH-1:0] ram_read_addr;
    wire signed [15:0] ram_read_data;

    reg rom_read_enable;
    reg [11:0] rom_phase_addr;
    wire signed [15:0] rom_sin_data;
    wire signed [15:0] rom_cos_data;

    reg [1:0] result_count_latched;
    reg [19:0] frequency_a;
    reg [19:0] frequency_b;
    reg [19:0] frequency_c;

    reg [20:0] divider_numerator;
    reg [19:0] divider_denominator;
    wire divider_start;
    wire divider_busy;
    wire divider_valid;
    wire divider_by_zero;
    wire [20:0] divider_quotient;
    reg [9:0] harmonic_order1;
    reg [9:0] harmonic_order2;
    reg [29:0] order_product;
    reg harmonic1_work_valid;
    reg harmonic2_work_valid;

    reg [1:0] tone_index;
    wire [19:0] current_frequency_hz;
    reg [19:0] tone_frequency_latched;
    (* use_dsp = "yes" *) reg [37:0] phase_increment_product;
    reg [31:0] phase_increment;
    reg [31:0] phase_accumulator;
    reg [ADDR_WIDTH-1:0] sample_index;
    (* use_dsp = "yes" *) reg signed [31:0] cosine_product;
    (* use_dsp = "yes" *) reg signed [31:0] sine_product;
    reg signed [47:0] cosine_accumulator;
    reg signed [47:0] sine_accumulator;

    wire cordic_start;
    wire cordic_busy;
    wire cordic_done;
    wire [15:0] cordic_angle_q16;
    reg [15:0] phase0_q16;
    reg [15:0] phase1_q16;
    reg [15:0] phase2_q16;
    reg phase0_nonzero;
    reg phase1_nonzero;
    reg phase2_nonzero;

    reg candidate1_valid;
    reg candidate2_valid;
    reg [8:0] candidate1_degree;
    reg [8:0] candidate2_degree;
    reg [15:0] relative1_q16;
    reg [15:0] relative2_q16;
    (* use_dsp = "yes" *) reg [24:0] degree_multiply_raw;
    (* use_dsp = "yes" *) reg [25:0] degree_product;

    reg previous_seen;
    reg [1:0] previous_count;
    reg previous1_valid;
    reg previous2_valid;
    reg [9:0] previous_order1;
    reg [9:0] previous_order2;
    reg [8:0] previous_degree1;
    reg [8:0] previous_degree2;
    reg stability_key_registered;
    reg [8:0] stability_distance1;
    reg [8:0] stability_distance2;
    reg stability_decision;

    wire stable_key_match;

    assign capture_fire = fft_valid && fft_ready;
    // A completed frame belongs to the next spectrum result until that result
    // explicitly consumes it.  Never let a newer FFT frame overwrite it,
    // even if the correlator itself is still idle.
    assign capture_write_enable = capture_fire && !busy &&
        !captured_frame_complete && !capture_dropping;
    assign busy = state != ST_IDLE;
    assign error_sticky = {
        phase_overrun_sticky,
        result_without_frame_sticky,
        capture_length_error_sticky
    };
    assign divider_start = (state == ST_ORDER1_START) ||
        (state == ST_ORDER2_START);
    assign cordic_start = state == ST_CORDIC_START;
    assign current_frequency_hz = (tone_index == 2'd0) ? frequency_a :
        ((tone_index == 2'd1) ? frequency_b : frequency_c);
    assign stable_key_match = previous_seen &&
        (previous_count == result_count_latched) &&
        (previous1_valid == candidate1_valid) &&
        (previous2_valid == candidate2_valid) &&
        (!candidate1_valid || (previous_order1 == harmonic_order1)) &&
        (!candidate2_valid || (previous_order2 == harmonic_order2));
    g_frame_ram #(
        .DATA_WIDTH(16), .ADDR_WIDTH(ADDR_WIDTH), .DEPTH(FRAME_LENGTH)
    ) phase_sample_ram (
        .clk(clk),
        .write_enable(capture_write_enable),
        .write_addr(capture_addr),
        .write_data(fft_real),
        .read_enable(ram_read_enable),
        .read_addr(ram_read_addr),
        .read_data(ram_read_data)
    );

    g_sine_cos_rom #(
        .COEFF_FILE(SINE_FILE)
    ) phase_reference_rom (
        .clk(clk),
        .read_enable(rom_read_enable),
        .phase_addr(rom_phase_addr),
        .sin_data(rom_sin_data),
        .cos_data(rom_cos_data)
    );

    g_unsigned_divider #(
        .NUMERATOR_WIDTH(21), .DENOMINATOR_WIDTH(20)
    ) harmonic_order_divider (
        .clk(clk), .rst_n(rst_n), .start(divider_start),
        .numerator(divider_numerator),
        .denominator(divider_denominator),
        .busy(divider_busy), .valid(divider_valid),
        .divide_by_zero(divider_by_zero),
        .quotient(divider_quotient)
    );

    g_cordic_atan2 phase_cordic (
        .clk(clk), .rst_n(rst_n), .start(cordic_start),
        .x_in(sine_accumulator), .y_in(cosine_accumulator),
        .busy(cordic_busy), .done(cordic_done),
        .angle_q16(cordic_angle_q16)
    );

    // Capture is independent of the relatively short correlation state
    // machine.  In the normal schedule a complete FFT frame is captured long
    // before the analyzer produces its result.  If a future scheduler change
    // creates overlap, the new frame is dropped instead of corrupting the
    // frame currently being correlated and a sticky diagnostic is raised.
    always @(posedge clk) begin
        if (!rst_n) begin
            capture_addr <= {ADDR_WIDTH{1'b0}};
            capture_dropping <= 1'b0;
            captured_frame_complete <= 1'b0;
            capture_length_error_sticky <= 1'b0;
            phase_overrun_sticky <= 1'b0;
        end else begin
            if (consume_frame)
                captured_frame_complete <= 1'b0;

            if (capture_fire) begin
                if ((capture_addr == {ADDR_WIDTH{1'b0}}) &&
                        (busy || captured_frame_complete)) begin
                    capture_dropping <= 1'b1;
                    phase_overrun_sticky <= 1'b1;
                end else if ((capture_addr != {ADDR_WIDTH{1'b0}}) &&
                        (busy || captured_frame_complete) &&
                        !capture_dropping) begin
                    capture_dropping <= 1'b1;
                    phase_overrun_sticky <= 1'b1;
                end

                if (fft_last) begin
                    // A deliberately dropped frame must not erase the ready
                    // flag of the older protected frame.  If that older frame
                    // was consumed while this one was being dropped, the
                    // consume_frame assignment above remains effective.
                    if (!capture_dropping && !busy &&
                            !captured_frame_complete) begin
                        if (capture_addr != FRAME_LENGTH-1)
                            capture_length_error_sticky <= 1'b1;
                        if (capture_addr == FRAME_LENGTH-1)
                            captured_frame_complete <= 1'b1;
                        else
                            captured_frame_complete <= 1'b0;
                    end
                    capture_addr <= {ADDR_WIDTH{1'b0}};
                    capture_dropping <= 1'b0;
                end else if (capture_addr == FRAME_LENGTH-1) begin
                    capture_length_error_sticky <= 1'b1;
                    captured_frame_complete <= 1'b0;
                    capture_addr <= {ADDR_WIDTH{1'b0}};
                    capture_dropping <= 1'b0;
                end else begin
                    capture_addr <= capture_addr+1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            consume_frame <= 1'b0;
            result_without_frame_sticky <= 1'b0;
            phase_results_valid <= 1'b0;
            harmonic1_phase_valid <= 1'b0;
            harmonic2_phase_valid <= 1'b0;
            harmonic1_phase_deg <= 9'd0;
            harmonic2_phase_deg <= 9'd0;
            result_count_latched <= 2'd0;
            frequency_a <= 20'd0;
            frequency_b <= 20'd0;
            frequency_c <= 20'd0;
            divider_numerator <= 21'd0;
            divider_denominator <= 20'd0;
            harmonic_order1 <= 10'd0;
            harmonic_order2 <= 10'd0;
            order_product <= 30'd0;
            harmonic1_work_valid <= 1'b0;
            harmonic2_work_valid <= 1'b0;
            tone_index <= 2'd0;
            tone_frequency_latched <= 20'd0;
            phase_increment_product <= 38'd0;
            phase_increment <= 32'd0;
            phase_accumulator <= 32'd0;
            sample_index <= {ADDR_WIDTH{1'b0}};
            ram_read_enable <= 1'b0;
            ram_read_addr <= {ADDR_WIDTH{1'b0}};
            rom_read_enable <= 1'b0;
            rom_phase_addr <= 12'd0;
            cosine_product <= 32'sd0;
            sine_product <= 32'sd0;
            cosine_accumulator <= 48'sd0;
            sine_accumulator <= 48'sd0;
            phase0_q16 <= 16'd0;
            phase1_q16 <= 16'd0;
            phase2_q16 <= 16'd0;
            phase0_nonzero <= 1'b0;
            phase1_nonzero <= 1'b0;
            phase2_nonzero <= 1'b0;
            candidate1_valid <= 1'b0;
            candidate2_valid <= 1'b0;
            candidate1_degree <= 9'd0;
            candidate2_degree <= 9'd0;
            relative1_q16 <= 16'd0;
            relative2_q16 <= 16'd0;
            degree_multiply_raw <= 25'd0;
            degree_product <= 26'd0;
            previous_seen <= 1'b0;
            previous_count <= 2'd0;
            previous1_valid <= 1'b0;
            previous2_valid <= 1'b0;
            previous_order1 <= 10'd0;
            previous_order2 <= 10'd0;
            previous_degree1 <= 9'd0;
            previous_degree2 <= 9'd0;
            stability_key_registered <= 1'b0;
            stability_distance1 <= 9'd0;
            stability_distance2 <= 9'd0;
            stability_decision <= 1'b0;
        end else begin
            phase_results_valid <= 1'b0;
            consume_frame <= 1'b0;
            ram_read_enable <= 1'b0;
            rom_read_enable <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (spectrum_results_valid) begin
                        if (!captured_frame_complete) begin
                            result_without_frame_sticky <= 1'b1;
                        end else begin
                            consume_frame <= 1'b1;
                            result_count_latched <= component_count;
                            frequency_a <= peak0_frequency_hz;
                            frequency_b <= (component_count >= 2) ?
                                peak1_frequency_hz : UNUSED_FREQUENCY;
                            frequency_c <= (component_count >= 3) ?
                                peak2_frequency_hz : UNUSED_FREQUENCY;
                            state <= ST_SORT_01;
                        end
                    end
                end

                ST_SORT_01: begin
                    if (frequency_a > frequency_b) begin
                        frequency_a <= frequency_b;
                        frequency_b <= frequency_a;
                    end
                    state <= ST_SORT_12;
                end

                ST_SORT_12: begin
                    if (frequency_b > frequency_c) begin
                        frequency_b <= frequency_c;
                        frequency_c <= frequency_b;
                    end
                    state <= ST_SORT_01_AGAIN;
                end

                ST_SORT_01_AGAIN: begin
                    if (frequency_a > frequency_b) begin
                        frequency_a <= frequency_b;
                        frequency_b <= frequency_a;
                    end
                    state <= ST_CHECK_COUNT;
                end

                ST_CHECK_COUNT: begin
                    harmonic_order1 <= 10'd0;
                    harmonic_order2 <= 10'd0;
                    harmonic1_work_valid <= 1'b0;
                    harmonic2_work_valid <= 1'b0;
                    candidate1_valid <= 1'b0;
                    candidate2_valid <= 1'b0;
                    candidate1_degree <= 9'd0;
                    candidate2_degree <= 9'd0;
                    phase0_nonzero <= 1'b0;
                    phase1_nonzero <= 1'b0;
                    phase2_nonzero <= 1'b0;
                    if ((result_count_latched < 2) ||
                            (frequency_a == 20'd0)) begin
                        state <= ST_STABILIZE;
                    end else begin
                        divider_numerator <= {1'b0, frequency_b}+
                            ({1'b0, frequency_a} >> 1);
                        divider_denominator <= frequency_a;
                        state <= ST_ORDER1_START;
                    end
                end

                ST_ORDER1_START:
                    state <= ST_ORDER1_WAIT;

                ST_ORDER1_WAIT: begin
                    if (divider_valid) begin
                        harmonic_order1 <= divider_quotient[9:0];
                        order_product <= divider_quotient[9:0]*frequency_a;
                        state <= ST_ORDER1_CHECK;
                    end
                end

                ST_ORDER1_CHECK: begin
                    harmonic1_work_valid <= !divider_by_zero &&
                        (harmonic_order1 >= 10'd2) &&
                        (((order_product >= frequency_b) &&
                          (order_product-frequency_b <= 30'd500)) ||
                         ((order_product < frequency_b) &&
                          (frequency_b-order_product <= 30'd500)));
                    if (result_count_latched >= 3) begin
                        divider_numerator <= {1'b0, frequency_c}+
                            ({1'b0, frequency_a} >> 1);
                        divider_denominator <= frequency_a;
                        state <= ST_ORDER2_START;
                    end else begin
                        tone_index <= 2'd0;
                        state <= ST_PHASE_INC_MUL;
                    end
                end

                ST_ORDER2_START:
                    state <= ST_ORDER2_WAIT;

                ST_ORDER2_WAIT: begin
                    if (divider_valid) begin
                        harmonic_order2 <= divider_quotient[9:0];
                        order_product <= divider_quotient[9:0]*frequency_a;
                        state <= ST_ORDER2_CHECK;
                    end
                end

                ST_ORDER2_CHECK: begin
                    harmonic2_work_valid <= !divider_by_zero &&
                        (harmonic_order2 >= 10'd2) &&
                        (harmonic_order2 != harmonic_order1) &&
                        (((order_product >= frequency_c) &&
                          (order_product-frequency_c <= 30'd500)) ||
                         ((order_product < frequency_c) &&
                          (frequency_c-order_product <= 30'd500)));
                    tone_index <= 2'd0;
                    state <= ST_PHASE_INC_MUL;
                end

                ST_PHASE_INC_MUL: begin
                    // Register the tone-select mux before the DSP input.
                    tone_frequency_latched <= current_frequency_hz;
                    state <= ST_PHASE_PRODUCT;
                end

                ST_PHASE_PRODUCT: begin
                    // 137439/64 approximates 2^32/2,000,000.  Its maximum
                    // equivalent frequency error below 600 kHz is 0.21 Hz.
                    phase_increment_product <=
                        tone_frequency_latched*18'd137439;
                    state <= ST_PHASE_INC_ROUND;
                end

                ST_PHASE_INC_ROUND: begin
                    phase_increment <= (phase_increment_product+38'd32) >> 6;
                    state <= ST_PASS_PREP;
                end

                ST_PASS_PREP: begin
                    sample_index <= {ADDR_WIDTH{1'b0}};
                    cosine_accumulator <= 48'sd0;
                    sine_accumulator <= 48'sd0;
                    // Low 32 bits intentionally implement modulo one turn.
                    phase_accumulator <= 32'd0-
                        ((phase_increment << 11)-phase_increment+
                         (phase_increment >> 1));
                    state <= ST_PASS_ISSUE;
                end

                ST_PASS_ISSUE: begin
                    ram_read_enable <= 1'b1;
                    ram_read_addr <= sample_index;
                    rom_read_enable <= 1'b1;
                    rom_phase_addr <= phase_accumulator[31:20];
                    phase_accumulator <= phase_accumulator+phase_increment;
                    state <= ST_PASS_WAIT;
                end

                ST_PASS_WAIT:
                    state <= ST_PASS_MULTIPLY;

                ST_PASS_MULTIPLY: begin
                    cosine_product <= ram_read_data*rom_cos_data;
                    sine_product <= ram_read_data*rom_sin_data;
                    state <= ST_PASS_ACCUMULATE;
                end

                ST_PASS_ACCUMULATE: begin
                    cosine_accumulator <= cosine_accumulator+cosine_product;
                    sine_accumulator <= sine_accumulator+sine_product;
                    if (sample_index == FRAME_LENGTH-1) begin
                        state <= ST_CORDIC_START;
                    end else begin
                        sample_index <= sample_index+1'b1;
                        state <= ST_PASS_ISSUE;
                    end
                end

                ST_CORDIC_START: begin
                    if (tone_index == 2'd0)
                        phase0_nonzero <= (cosine_accumulator != 48'sd0) ||
                            (sine_accumulator != 48'sd0);
                    else if (tone_index == 2'd1)
                        phase1_nonzero <= (cosine_accumulator != 48'sd0) ||
                            (sine_accumulator != 48'sd0);
                    else
                        phase2_nonzero <= (cosine_accumulator != 48'sd0) ||
                            (sine_accumulator != 48'sd0);
                    state <= ST_CORDIC_WAIT;
                end

                ST_CORDIC_WAIT: begin
                    if (cordic_done) begin
                        if (tone_index == 2'd0) begin
                            phase0_q16 <= cordic_angle_q16;
                            if (harmonic1_work_valid) begin
                                tone_index <= 2'd1;
                                state <= ST_PHASE_INC_MUL;
                            end else if (harmonic2_work_valid) begin
                                tone_index <= 2'd2;
                                state <= ST_PHASE_INC_MUL;
                            end else begin
                                state <= ST_RELATIVE1;
                            end
                        end else if (tone_index == 2'd1) begin
                            phase1_q16 <= cordic_angle_q16;
                            if (harmonic2_work_valid) begin
                                tone_index <= 2'd2;
                                state <= ST_PHASE_INC_MUL;
                            end else begin
                                state <= ST_RELATIVE1;
                            end
                        end else begin
                            phase2_q16 <= cordic_angle_q16;
                            state <= ST_RELATIVE1;
                        end
                    end
                end

                ST_RELATIVE1: begin
                    candidate1_valid <= harmonic1_work_valid &&
                        phase0_nonzero && phase1_nonzero;
                    relative1_q16 <= phase1_q16-
                        (phase0_q16*harmonic_order1);
                    state <= ST_DEGREE1_MUL;
                end

                ST_DEGREE1_MUL: begin
                    degree_multiply_raw <= relative1_q16*9'd360;
                    state <= ST_DEGREE1_ADD;
                end

                ST_DEGREE1_ADD: begin
                    degree_product <=
                        {1'b0, degree_multiply_raw}+26'd32768;
                    state <= ST_DEGREE1_ROUND;
                end

                ST_DEGREE1_ROUND: begin
                    if (degree_product[25:16] >= 10'd360)
                        candidate1_degree <= 9'd0;
                    else
                        candidate1_degree <= degree_product[24:16];
                    state <= ST_RELATIVE2;
                end

                ST_RELATIVE2: begin
                    candidate2_valid <= harmonic2_work_valid &&
                        phase0_nonzero && phase2_nonzero;
                    relative2_q16 <= phase2_q16-
                        (phase0_q16*harmonic_order2);
                    state <= ST_DEGREE2_MUL;
                end

                ST_DEGREE2_MUL: begin
                    degree_multiply_raw <= relative2_q16*9'd360;
                    state <= ST_DEGREE2_ADD;
                end

                ST_DEGREE2_ADD: begin
                    degree_product <=
                        {1'b0, degree_multiply_raw}+26'd32768;
                    state <= ST_DEGREE2_ROUND;
                end

                ST_DEGREE2_ROUND: begin
                    if (degree_product[25:16] >= 10'd360)
                        candidate2_degree <= 9'd0;
                    else
                        candidate2_degree <= degree_product[24:16];
                    state <= ST_STABILIZE;
                end

                ST_STABILIZE: begin
                    // First calculate ordinary absolute differences.  The
                    // circular 360-difference correction is a separate cycle
                    // so neither operation shares a carry chain at 200 MHz.
                    stability_key_registered <= stable_key_match;
                    if (candidate1_degree >= previous_degree1)
                        stability_distance1 <=
                            candidate1_degree-previous_degree1;
                    else
                        stability_distance1 <=
                            previous_degree1-candidate1_degree;
                    if (candidate2_degree >= previous_degree2)
                        stability_distance2 <=
                            candidate2_degree-previous_degree2;
                    else
                        stability_distance2 <=
                            previous_degree2-candidate2_degree;
                    state <= ST_STABILITY_WRAP;
                end

                ST_STABILITY_WRAP: begin
                    if (stability_distance1 > 9'd180)
                        stability_distance1 <=
                            9'd360-stability_distance1;
                    if (stability_distance2 > 9'd180)
                        stability_distance2 <=
                            9'd360-stability_distance2;
                    state <= ST_STABILITY_DECIDE;
                end

                ST_STABILITY_DECIDE: begin
                    stability_decision <= stability_key_registered &&
                        (!candidate1_valid ||
                         stability_distance1 <= 9'd3) &&
                        (!candidate2_valid ||
                         stability_distance2 <= 9'd3);
                    state <= ST_PUBLISH;
                end

                ST_PUBLISH: begin
                    if (stability_decision) begin
                        harmonic1_phase_valid <= candidate1_valid;
                        harmonic2_phase_valid <= candidate2_valid;
                        harmonic1_phase_deg <= candidate1_degree;
                        harmonic2_phase_deg <= candidate2_degree;
                        phase_results_valid <= 1'b1;
                    end
                    previous_seen <= 1'b1;
                    previous_count <= result_count_latched;
                    previous1_valid <= candidate1_valid;
                    previous2_valid <= candidate2_valid;
                    previous_order1 <= harmonic_order1;
                    previous_order2 <= harmonic_order2;
                    previous_degree1 <= candidate1_degree;
                    previous_degree2 <= candidate2_degree;
                    state <= ST_IDLE;
                end

                default:
                    state <= ST_IDLE;
            endcase
        end
    end

    initial begin
        if (FRAME_LENGTH != 4096)
            $error("g_phase_estimator currently requires FRAME_LENGTH=4096");
        if (SAMPLE_RATE_HZ != 2000000)
            $error("g_phase_estimator phase-increment constant requires 2 MSPS");
    end

endmodule
