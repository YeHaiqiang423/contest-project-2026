`timescale 1ns/1ps

// Decimate a 20 MSPS valid stream to 2 MSPS and collect ping-pong frames.
// The default 4096-sample frame spans 2.048 ms at the output sample rate.
module g_frame_capture #(
    parameter integer DATA_WIDTH = 16,
    parameter integer DECIMATION = 10,
    parameter integer FRAME_LENGTH = 4096,
    parameter integer ADDR_WIDTH = 12
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         capture_enable,
    input  wire                         sample_valid,
    input  wire signed [DATA_WIDTH-1:0] sample_data,

    output reg                          frame_ready,
    output reg                          frame_bank,
    output reg  [1:0]                   bank_pending,
    output reg                          capture_stalled,
    output reg                          frame_overrun,

    input  wire                         read_enable,
    input  wire                         read_bank,
    input  wire [ADDR_WIDTH-1:0]        read_addr,
    output wire signed [DATA_WIDTH-1:0] read_data,
    input  wire                         release_valid,
    input  wire                         release_bank
);

    function integer clog2;
        input integer value;
        integer working;
        begin
            working = value-1;
            for (clog2 = 0; working > 0; clog2 = clog2+1)
                working = working >> 1;
        end
    endfunction

    localparam integer DECIM_WIDTH = (DECIMATION <= 1) ? 1 : clog2(DECIMATION);

    reg [DECIM_WIDTH-1:0] decimation_count;
    reg [ADDR_WIDTH-1:0] write_addr;
    reg write_bank;
    reg read_bank_delayed;
    wire write_selected_sample;
    wire write_enable_bank0;
    wire write_enable_bank1;
    wire signed [DATA_WIDTH-1:0] read_data_bank0;
    wire signed [DATA_WIDTH-1:0] read_data_bank1;

    assign write_selected_sample = capture_enable && sample_valid &&
        !capture_stalled && (decimation_count == {DECIM_WIDTH{1'b0}});
    assign write_enable_bank0 = write_selected_sample && !write_bank;
    assign write_enable_bank1 = write_selected_sample && write_bank;
    assign read_data = read_bank_delayed ? read_data_bank1 : read_data_bank0;

    g_frame_ram #(
        .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .DEPTH(FRAME_LENGTH)
    ) bank0_ram (
        .clk(clk), .write_enable(write_enable_bank0), .write_addr(write_addr),
        .write_data(sample_data), .read_enable(read_enable && !read_bank),
        .read_addr(read_addr), .read_data(read_data_bank0)
    );

    g_frame_ram #(
        .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .DEPTH(FRAME_LENGTH)
    ) bank1_ram (
        .clk(clk), .write_enable(write_enable_bank1), .write_addr(write_addr),
        .write_data(sample_data), .read_enable(read_enable && read_bank),
        .read_addr(read_addr), .read_data(read_data_bank1)
    );

    initial begin
        if (DECIMATION < 1)
            $error("DECIMATION must be positive");
        if (FRAME_LENGTH < 2)
            $error("FRAME_LENGTH must be at least two");
        if ((1 << ADDR_WIDTH) < FRAME_LENGTH)
            $error("ADDR_WIDTH cannot address the full frame");
    end

    always @(posedge clk) begin
        if (!rst_n)
            read_bank_delayed <= 1'b0;
        else if (read_enable)
            read_bank_delayed <= read_bank;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            frame_ready <= 1'b0;
            frame_bank <= 1'b0;
            bank_pending <= 2'b00;
            capture_stalled <= 1'b0;
            frame_overrun <= 1'b0;
            decimation_count <= {DECIM_WIDTH{1'b0}};
            write_addr <= {ADDR_WIDTH{1'b0}};
            write_bank <= 1'b0;
        end else begin
            frame_ready <= 1'b0;

            if (release_valid) begin
                if (release_bank)
                    bank_pending[1] <= 1'b0;
                else
                    bank_pending[0] <= 1'b0;
                if (capture_stalled) begin
                    capture_stalled <= 1'b0;
                    write_bank <= release_bank;
                    write_addr <= {ADDR_WIDTH{1'b0}};
                    decimation_count <= {DECIM_WIDTH{1'b0}};
                end
            end

            if (!capture_enable) begin
                decimation_count <= {DECIM_WIDTH{1'b0}};
                write_addr <= {ADDR_WIDTH{1'b0}};
            end else if (sample_valid) begin
                if (capture_stalled) begin
                    frame_overrun <= 1'b1;
                end else begin
                    if (decimation_count == {DECIM_WIDTH{1'b0}}) begin
                        if (write_addr == FRAME_LENGTH-1) begin
                            frame_ready <= 1'b1;
                            frame_bank <= write_bank;
                            if (write_bank)
                                bank_pending[1] <= 1'b1;
                            else
                                bank_pending[0] <= 1'b1;
                            write_addr <= {ADDR_WIDTH{1'b0}};

                            if (bank_pending[~write_bank]) begin
                                capture_stalled <= 1'b1;
                                frame_overrun <= 1'b1;
                            end else begin
                                write_bank <= ~write_bank;
                            end
                        end else begin
                            write_addr <= write_addr+1'b1;
                        end
                    end

                    if (decimation_count == DECIMATION-1)
                        decimation_count <= {DECIM_WIDTH{1'b0}};
                    else
                        decimation_count <= decimation_count+1'b1;
                end
            end
        end
    end

endmodule
