`timescale 1ns/1ps

// Read one completed frame, apply a symmetric Q15 Hann window, and present
// real/imaginary samples through a ready/valid interface suitable for FFT IP.
module g_fft_input_stream #(
    parameter integer DATA_WIDTH = 16,
    parameter integer FRAME_LENGTH = 4096,
    parameter integer ADDR_WIDTH = 12,
    parameter integer COEFF_WIDTH = 16,
    parameter integer COEFF_ADDR_WIDTH = 11,
    parameter COEFF_FILE = "matlab/vectors/g_hann_q15_unique.hex"
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire                         start_bank,
    output reg                          busy,

    output wire                         frame_read_enable,
    output wire                         frame_read_bank,
    output wire [ADDR_WIDTH-1:0]        frame_read_addr,
    input  wire signed [DATA_WIDTH-1:0] frame_read_data,

    output reg                          fft_valid,
    input  wire                         fft_ready,
    output reg signed [DATA_WIDTH-1:0] fft_real,
    output reg signed [DATA_WIDTH-1:0] fft_imag,
    output reg                          fft_last,

    output reg                          release_valid,
    output reg                          release_bank
);

    localparam integer PRODUCT_WIDTH = DATA_WIDTH+COEFF_WIDTH;
    reg active_bank;
    reg [ADDR_WIDTH-1:0] next_addr;
    reg [ADDR_WIDTH-1:0] pending_addr;
    reg [ADDR_WIDTH-1:0] sample_addr;
    reg [ADDR_WIDTH-1:0] product_addr;
    reg read_pending;
    reg sample_pending;
    reg multiply_pending;
    reg signed [DATA_WIDTH-1:0] sample_stage;
    reg signed [COEFF_WIDTH-1:0] coeff_stage;
    reg signed [PRODUCT_WIDTH-1:0] product_stage;

    wire issue_read;
    wire [ADDR_WIDTH-1:0] mirrored_addr;
    wire [COEFF_ADDR_WIDTH-1:0] window_addr;
    wire signed [COEFF_WIDTH-1:0] window_coeff;

    assign issue_read = busy && !read_pending && !sample_pending &&
        !multiply_pending && !fft_valid;
    assign frame_read_enable = issue_read;
    assign frame_read_bank = active_bank;
    assign frame_read_addr = next_addr;
    assign mirrored_addr = (next_addr < FRAME_LENGTH/2) ?
        next_addr : FRAME_LENGTH-1-next_addr;
    assign window_addr = mirrored_addr[COEFF_ADDR_WIDTH-1:0];

    g_hann_rom #(
        .COEFF_WIDTH(COEFF_WIDTH),
        .ADDR_WIDTH(COEFF_ADDR_WIDTH),
        .DEPTH(FRAME_LENGTH/2),
        .COEFF_FILE(COEFF_FILE)
    ) window_rom (
        .clk(clk),
        .read_enable(issue_read),
        .read_addr(window_addr),
        .read_data(window_coeff)
    );

    function signed [DATA_WIDTH-1:0] round_q15;
        input signed [PRODUCT_WIDTH-1:0] value;
        reg signed [PRODUCT_WIDTH-1:0] rounded;
        begin
            rounded = value + ({{(PRODUCT_WIDTH-1){1'b0}}, 1'b1} << 14);
            round_q15 = rounded >>> 15;
        end
    endfunction

    initial begin
        if ((FRAME_LENGTH & (FRAME_LENGTH-1)) != 0)
            $error("FRAME_LENGTH must be a power of two");
        if ((1 << ADDR_WIDTH) < FRAME_LENGTH)
            $error("ADDR_WIDTH cannot address the full frame");
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            active_bank <= 1'b0;
            next_addr <= {ADDR_WIDTH{1'b0}};
            pending_addr <= {ADDR_WIDTH{1'b0}};
            sample_addr <= {ADDR_WIDTH{1'b0}};
            product_addr <= {ADDR_WIDTH{1'b0}};
            read_pending <= 1'b0;
            sample_pending <= 1'b0;
            multiply_pending <= 1'b0;
            sample_stage <= {DATA_WIDTH{1'b0}};
            coeff_stage <= {COEFF_WIDTH{1'b0}};
            product_stage <= {PRODUCT_WIDTH{1'b0}};
            fft_valid <= 1'b0;
            fft_real <= {DATA_WIDTH{1'b0}};
            fft_imag <= {DATA_WIDTH{1'b0}};
            fft_last <= 1'b0;
            release_valid <= 1'b0;
            release_bank <= 1'b0;
        end else begin
            release_valid <= 1'b0;

            if (start && !busy) begin
                busy <= 1'b1;
                active_bank <= start_bank;
                next_addr <= {ADDR_WIDTH{1'b0}};
            end

            if (issue_read) begin
                pending_addr <= next_addr;
                read_pending <= 1'b1;
                if (next_addr != FRAME_LENGTH-1)
                    next_addr <= next_addr+1'b1;
            end

            if (read_pending) begin
                sample_stage <= frame_read_data;
                coeff_stage <= window_coeff;
                sample_addr <= pending_addr;
                read_pending <= 1'b0;
                sample_pending <= 1'b1;
            end

            if (sample_pending) begin
                product_stage <= sample_stage*coeff_stage;
                product_addr <= sample_addr;
                sample_pending <= 1'b0;
                multiply_pending <= 1'b1;
            end

            if (multiply_pending) begin
                fft_real <= round_q15(product_stage);
                fft_imag <= {DATA_WIDTH{1'b0}};
                fft_last <= (product_addr == FRAME_LENGTH-1);
                fft_valid <= 1'b1;
                multiply_pending <= 1'b0;
            end

            if (fft_valid && fft_ready) begin
                fft_valid <= 1'b0;
                if (fft_last) begin
                    busy <= 1'b0;
                    release_valid <= 1'b1;
                    release_bank <= active_bank;
                end
            end
        end
    end

endmodule
