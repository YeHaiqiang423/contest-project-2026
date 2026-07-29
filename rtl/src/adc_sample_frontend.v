`timescale 1ns/1ps

// Normalize one ADS6149 parallel-CMOS stream and retain one sample in ten.
// This block starts after the I/O capture registers in the 200 MHz ADC domain.
// The external analog filter is responsible for anti-aliasing before /10.
module adc_sample_frontend #(
    parameter integer ADC_WIDTH = 14,
    parameter integer DECIMATION = 10,
    parameter integer INPUT_OFFSET_BINARY = 0
) (
    input  wire                        clk_adc,
    input  wire                        rst_n,
    input  wire                        adc_valid,
    input  wire [ADC_WIDTH-1:0]        adc_data,
    output reg                         sample_valid,
    output reg signed [ADC_WIDTH-1:0] sample_data
);

    function integer clog2;
        input integer value;
        integer working;
        begin
            working = value - 1;
            for (clog2 = 0; working > 0; clog2 = clog2 + 1)
                working = working >> 1;
        end
    endfunction

    localparam integer COUNT_WIDTH = (DECIMATION <= 1) ? 1 : clog2(DECIMATION);
    reg [COUNT_WIDTH-1:0] decimation_count;
    wire [ADC_WIDTH-1:0] normalized_data;

    // Toggling the MSB maps offset binary into two's-complement bit coding.
    assign normalized_data = INPUT_OFFSET_BINARY ?
        {~adc_data[ADC_WIDTH-1], adc_data[ADC_WIDTH-2:0]} : adc_data;

    initial begin
        if (ADC_WIDTH < 2)
            $error("ADC_WIDTH must be at least two");
        if (DECIMATION < 1)
            $error("DECIMATION must be positive");
    end

    always @(posedge clk_adc) begin
        if (!rst_n) begin
            decimation_count <= {COUNT_WIDTH{1'b0}};
            sample_valid <= 1'b0;
            sample_data <= {ADC_WIDTH{1'b0}};
        end else begin
            sample_valid <= 1'b0;
            if (adc_valid) begin
                if (decimation_count == {COUNT_WIDTH{1'b0}}) begin
                    sample_valid <= 1'b1;
                    sample_data <= normalized_data;
                end
                if (decimation_count == DECIMATION-1)
                    decimation_count <= {COUNT_WIDTH{1'b0}};
                else
                    decimation_count <= decimation_count + 1'b1;
            end
        end
    end

endmodule
