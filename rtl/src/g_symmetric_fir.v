`timescale 1ns/1ps

// 255-tap symmetric FIR for a 20 MSPS stream in a 200 MHz clock domain.
// Thirteen multipliers process 128 unique taps over ten clock cycles.
module g_symmetric_fir #(
    parameter integer INPUT_WIDTH = 14,
    parameter integer OUTPUT_WIDTH = 16,
    parameter integer COEFF_WIDTH = 18,
    parameter integer COEFF_FRACTION = 17,
    parameter COEFF_FILE = "matlab/vectors/g_lpf_q17_unique.hex"
) (
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            sample_valid,
    input  wire signed [INPUT_WIDTH-1:0]   sample_data,
    output reg                             output_valid,
    output reg signed [OUTPUT_WIDTH-1:0]  output_data,
    output reg                             input_overrun
);

    localparam integer TAP_COUNT = 255;
    localparam integer UNIQUE_TAPS = 128;
    localparam integer LANES = 13;
    localparam integer PHASES = 10;
    localparam integer PAIR_WIDTH = INPUT_WIDTH+1;
    localparam integer PRODUCT_WIDTH = PAIR_WIDTH+COEFF_WIDTH;
    localparam integer SUM_WIDTH = 36;

    reg signed [INPUT_WIDTH-1:0] delay_line [0:TAP_COUNT-1];
    reg signed [COEFF_WIDTH-1:0] coeff_memory [0:UNIQUE_TAPS-1];
    reg signed [INPUT_WIDTH-1:0] selected_left [0:LANES-1];
    reg signed [INPUT_WIDTH-1:0] selected_right [0:LANES-1];
    reg signed [COEFF_WIDTH-1:0] selected_coeff [0:LANES-1];
    reg signed [INPUT_WIDTH-1:0] left_stage [0:LANES-1];
    reg signed [INPUT_WIDTH-1:0] right_stage [0:LANES-1];
    reg signed [COEFF_WIDTH-1:0] coeff_select_stage [0:LANES-1];
    reg signed [PAIR_WIDTH-1:0] pair_stage [0:LANES-1];
    reg signed [COEFF_WIDTH-1:0] coeff_stage [0:LANES-1];
    reg signed [PRODUCT_WIDTH-1:0] product_stage [0:LANES-1];
    reg signed [SUM_WIDTH-1:0] add_level1 [0:6];
    reg signed [SUM_WIDTH-1:0] add_level2 [0:3];
    reg signed [SUM_WIDTH-1:0] add_level3 [0:1];
    reg signed [SUM_WIDTH-1:0] add_level4;
    reg signed [SUM_WIDTH-1:0] accumulator;
    reg signed [SUM_WIDTH-1:0] final_sum;

    reg active;
    reg [3:0] phase;
    reg valid_select;
    reg valid_pair;
    reg valid_product;
    reg valid_level1;
    reg valid_level2;
    reg valid_level3;
    reg valid_level4;
    reg valid_final;
    reg [3:0] tag_select;
    reg [3:0] tag_pair;
    reg [3:0] tag_product;
    reg [3:0] tag_level1;
    reg [3:0] tag_level2;
    reg [3:0] tag_level3;
    reg [3:0] tag_level4;

    integer initialize_index;
    integer shift_index;
    integer select_lane;
    integer product_lane;

    initial begin
        $readmemh(COEFF_FILE, coeff_memory);
    end

    always @* begin
        for (select_lane = 0; select_lane < LANES; select_lane = select_lane+1) begin
            selected_left[select_lane] = {INPUT_WIDTH{1'b0}};
            selected_right[select_lane] = {INPUT_WIDTH{1'b0}};
            selected_coeff[select_lane] = {COEFF_WIDTH{1'b0}};
        end
        case (phase)
            4'd0: begin
                selected_left[0] = delay_line[0];
                selected_right[0] = delay_line[254];
                selected_coeff[0] = coeff_memory[0];
                selected_left[1] = delay_line[1];
                selected_right[1] = delay_line[253];
                selected_coeff[1] = coeff_memory[1];
                selected_left[2] = delay_line[2];
                selected_right[2] = delay_line[252];
                selected_coeff[2] = coeff_memory[2];
                selected_left[3] = delay_line[3];
                selected_right[3] = delay_line[251];
                selected_coeff[3] = coeff_memory[3];
                selected_left[4] = delay_line[4];
                selected_right[4] = delay_line[250];
                selected_coeff[4] = coeff_memory[4];
                selected_left[5] = delay_line[5];
                selected_right[5] = delay_line[249];
                selected_coeff[5] = coeff_memory[5];
                selected_left[6] = delay_line[6];
                selected_right[6] = delay_line[248];
                selected_coeff[6] = coeff_memory[6];
                selected_left[7] = delay_line[7];
                selected_right[7] = delay_line[247];
                selected_coeff[7] = coeff_memory[7];
                selected_left[8] = delay_line[8];
                selected_right[8] = delay_line[246];
                selected_coeff[8] = coeff_memory[8];
                selected_left[9] = delay_line[9];
                selected_right[9] = delay_line[245];
                selected_coeff[9] = coeff_memory[9];
                selected_left[10] = delay_line[10];
                selected_right[10] = delay_line[244];
                selected_coeff[10] = coeff_memory[10];
                selected_left[11] = delay_line[11];
                selected_right[11] = delay_line[243];
                selected_coeff[11] = coeff_memory[11];
                selected_left[12] = delay_line[12];
                selected_right[12] = delay_line[242];
                selected_coeff[12] = coeff_memory[12];
            end
            4'd1: begin
                selected_left[0] = delay_line[13];
                selected_right[0] = delay_line[241];
                selected_coeff[0] = coeff_memory[13];
                selected_left[1] = delay_line[14];
                selected_right[1] = delay_line[240];
                selected_coeff[1] = coeff_memory[14];
                selected_left[2] = delay_line[15];
                selected_right[2] = delay_line[239];
                selected_coeff[2] = coeff_memory[15];
                selected_left[3] = delay_line[16];
                selected_right[3] = delay_line[238];
                selected_coeff[3] = coeff_memory[16];
                selected_left[4] = delay_line[17];
                selected_right[4] = delay_line[237];
                selected_coeff[4] = coeff_memory[17];
                selected_left[5] = delay_line[18];
                selected_right[5] = delay_line[236];
                selected_coeff[5] = coeff_memory[18];
                selected_left[6] = delay_line[19];
                selected_right[6] = delay_line[235];
                selected_coeff[6] = coeff_memory[19];
                selected_left[7] = delay_line[20];
                selected_right[7] = delay_line[234];
                selected_coeff[7] = coeff_memory[20];
                selected_left[8] = delay_line[21];
                selected_right[8] = delay_line[233];
                selected_coeff[8] = coeff_memory[21];
                selected_left[9] = delay_line[22];
                selected_right[9] = delay_line[232];
                selected_coeff[9] = coeff_memory[22];
                selected_left[10] = delay_line[23];
                selected_right[10] = delay_line[231];
                selected_coeff[10] = coeff_memory[23];
                selected_left[11] = delay_line[24];
                selected_right[11] = delay_line[230];
                selected_coeff[11] = coeff_memory[24];
                selected_left[12] = delay_line[25];
                selected_right[12] = delay_line[229];
                selected_coeff[12] = coeff_memory[25];
            end
            4'd2: begin
                selected_left[0] = delay_line[26];
                selected_right[0] = delay_line[228];
                selected_coeff[0] = coeff_memory[26];
                selected_left[1] = delay_line[27];
                selected_right[1] = delay_line[227];
                selected_coeff[1] = coeff_memory[27];
                selected_left[2] = delay_line[28];
                selected_right[2] = delay_line[226];
                selected_coeff[2] = coeff_memory[28];
                selected_left[3] = delay_line[29];
                selected_right[3] = delay_line[225];
                selected_coeff[3] = coeff_memory[29];
                selected_left[4] = delay_line[30];
                selected_right[4] = delay_line[224];
                selected_coeff[4] = coeff_memory[30];
                selected_left[5] = delay_line[31];
                selected_right[5] = delay_line[223];
                selected_coeff[5] = coeff_memory[31];
                selected_left[6] = delay_line[32];
                selected_right[6] = delay_line[222];
                selected_coeff[6] = coeff_memory[32];
                selected_left[7] = delay_line[33];
                selected_right[7] = delay_line[221];
                selected_coeff[7] = coeff_memory[33];
                selected_left[8] = delay_line[34];
                selected_right[8] = delay_line[220];
                selected_coeff[8] = coeff_memory[34];
                selected_left[9] = delay_line[35];
                selected_right[9] = delay_line[219];
                selected_coeff[9] = coeff_memory[35];
                selected_left[10] = delay_line[36];
                selected_right[10] = delay_line[218];
                selected_coeff[10] = coeff_memory[36];
                selected_left[11] = delay_line[37];
                selected_right[11] = delay_line[217];
                selected_coeff[11] = coeff_memory[37];
                selected_left[12] = delay_line[38];
                selected_right[12] = delay_line[216];
                selected_coeff[12] = coeff_memory[38];
            end
            4'd3: begin
                selected_left[0] = delay_line[39];
                selected_right[0] = delay_line[215];
                selected_coeff[0] = coeff_memory[39];
                selected_left[1] = delay_line[40];
                selected_right[1] = delay_line[214];
                selected_coeff[1] = coeff_memory[40];
                selected_left[2] = delay_line[41];
                selected_right[2] = delay_line[213];
                selected_coeff[2] = coeff_memory[41];
                selected_left[3] = delay_line[42];
                selected_right[3] = delay_line[212];
                selected_coeff[3] = coeff_memory[42];
                selected_left[4] = delay_line[43];
                selected_right[4] = delay_line[211];
                selected_coeff[4] = coeff_memory[43];
                selected_left[5] = delay_line[44];
                selected_right[5] = delay_line[210];
                selected_coeff[5] = coeff_memory[44];
                selected_left[6] = delay_line[45];
                selected_right[6] = delay_line[209];
                selected_coeff[6] = coeff_memory[45];
                selected_left[7] = delay_line[46];
                selected_right[7] = delay_line[208];
                selected_coeff[7] = coeff_memory[46];
                selected_left[8] = delay_line[47];
                selected_right[8] = delay_line[207];
                selected_coeff[8] = coeff_memory[47];
                selected_left[9] = delay_line[48];
                selected_right[9] = delay_line[206];
                selected_coeff[9] = coeff_memory[48];
                selected_left[10] = delay_line[49];
                selected_right[10] = delay_line[205];
                selected_coeff[10] = coeff_memory[49];
                selected_left[11] = delay_line[50];
                selected_right[11] = delay_line[204];
                selected_coeff[11] = coeff_memory[50];
                selected_left[12] = delay_line[51];
                selected_right[12] = delay_line[203];
                selected_coeff[12] = coeff_memory[51];
            end
            4'd4: begin
                selected_left[0] = delay_line[52];
                selected_right[0] = delay_line[202];
                selected_coeff[0] = coeff_memory[52];
                selected_left[1] = delay_line[53];
                selected_right[1] = delay_line[201];
                selected_coeff[1] = coeff_memory[53];
                selected_left[2] = delay_line[54];
                selected_right[2] = delay_line[200];
                selected_coeff[2] = coeff_memory[54];
                selected_left[3] = delay_line[55];
                selected_right[3] = delay_line[199];
                selected_coeff[3] = coeff_memory[55];
                selected_left[4] = delay_line[56];
                selected_right[4] = delay_line[198];
                selected_coeff[4] = coeff_memory[56];
                selected_left[5] = delay_line[57];
                selected_right[5] = delay_line[197];
                selected_coeff[5] = coeff_memory[57];
                selected_left[6] = delay_line[58];
                selected_right[6] = delay_line[196];
                selected_coeff[6] = coeff_memory[58];
                selected_left[7] = delay_line[59];
                selected_right[7] = delay_line[195];
                selected_coeff[7] = coeff_memory[59];
                selected_left[8] = delay_line[60];
                selected_right[8] = delay_line[194];
                selected_coeff[8] = coeff_memory[60];
                selected_left[9] = delay_line[61];
                selected_right[9] = delay_line[193];
                selected_coeff[9] = coeff_memory[61];
                selected_left[10] = delay_line[62];
                selected_right[10] = delay_line[192];
                selected_coeff[10] = coeff_memory[62];
                selected_left[11] = delay_line[63];
                selected_right[11] = delay_line[191];
                selected_coeff[11] = coeff_memory[63];
                selected_left[12] = delay_line[64];
                selected_right[12] = delay_line[190];
                selected_coeff[12] = coeff_memory[64];
            end
            4'd5: begin
                selected_left[0] = delay_line[65];
                selected_right[0] = delay_line[189];
                selected_coeff[0] = coeff_memory[65];
                selected_left[1] = delay_line[66];
                selected_right[1] = delay_line[188];
                selected_coeff[1] = coeff_memory[66];
                selected_left[2] = delay_line[67];
                selected_right[2] = delay_line[187];
                selected_coeff[2] = coeff_memory[67];
                selected_left[3] = delay_line[68];
                selected_right[3] = delay_line[186];
                selected_coeff[3] = coeff_memory[68];
                selected_left[4] = delay_line[69];
                selected_right[4] = delay_line[185];
                selected_coeff[4] = coeff_memory[69];
                selected_left[5] = delay_line[70];
                selected_right[5] = delay_line[184];
                selected_coeff[5] = coeff_memory[70];
                selected_left[6] = delay_line[71];
                selected_right[6] = delay_line[183];
                selected_coeff[6] = coeff_memory[71];
                selected_left[7] = delay_line[72];
                selected_right[7] = delay_line[182];
                selected_coeff[7] = coeff_memory[72];
                selected_left[8] = delay_line[73];
                selected_right[8] = delay_line[181];
                selected_coeff[8] = coeff_memory[73];
                selected_left[9] = delay_line[74];
                selected_right[9] = delay_line[180];
                selected_coeff[9] = coeff_memory[74];
                selected_left[10] = delay_line[75];
                selected_right[10] = delay_line[179];
                selected_coeff[10] = coeff_memory[75];
                selected_left[11] = delay_line[76];
                selected_right[11] = delay_line[178];
                selected_coeff[11] = coeff_memory[76];
                selected_left[12] = delay_line[77];
                selected_right[12] = delay_line[177];
                selected_coeff[12] = coeff_memory[77];
            end
            4'd6: begin
                selected_left[0] = delay_line[78];
                selected_right[0] = delay_line[176];
                selected_coeff[0] = coeff_memory[78];
                selected_left[1] = delay_line[79];
                selected_right[1] = delay_line[175];
                selected_coeff[1] = coeff_memory[79];
                selected_left[2] = delay_line[80];
                selected_right[2] = delay_line[174];
                selected_coeff[2] = coeff_memory[80];
                selected_left[3] = delay_line[81];
                selected_right[3] = delay_line[173];
                selected_coeff[3] = coeff_memory[81];
                selected_left[4] = delay_line[82];
                selected_right[4] = delay_line[172];
                selected_coeff[4] = coeff_memory[82];
                selected_left[5] = delay_line[83];
                selected_right[5] = delay_line[171];
                selected_coeff[5] = coeff_memory[83];
                selected_left[6] = delay_line[84];
                selected_right[6] = delay_line[170];
                selected_coeff[6] = coeff_memory[84];
                selected_left[7] = delay_line[85];
                selected_right[7] = delay_line[169];
                selected_coeff[7] = coeff_memory[85];
                selected_left[8] = delay_line[86];
                selected_right[8] = delay_line[168];
                selected_coeff[8] = coeff_memory[86];
                selected_left[9] = delay_line[87];
                selected_right[9] = delay_line[167];
                selected_coeff[9] = coeff_memory[87];
                selected_left[10] = delay_line[88];
                selected_right[10] = delay_line[166];
                selected_coeff[10] = coeff_memory[88];
                selected_left[11] = delay_line[89];
                selected_right[11] = delay_line[165];
                selected_coeff[11] = coeff_memory[89];
                selected_left[12] = delay_line[90];
                selected_right[12] = delay_line[164];
                selected_coeff[12] = coeff_memory[90];
            end
            4'd7: begin
                selected_left[0] = delay_line[91];
                selected_right[0] = delay_line[163];
                selected_coeff[0] = coeff_memory[91];
                selected_left[1] = delay_line[92];
                selected_right[1] = delay_line[162];
                selected_coeff[1] = coeff_memory[92];
                selected_left[2] = delay_line[93];
                selected_right[2] = delay_line[161];
                selected_coeff[2] = coeff_memory[93];
                selected_left[3] = delay_line[94];
                selected_right[3] = delay_line[160];
                selected_coeff[3] = coeff_memory[94];
                selected_left[4] = delay_line[95];
                selected_right[4] = delay_line[159];
                selected_coeff[4] = coeff_memory[95];
                selected_left[5] = delay_line[96];
                selected_right[5] = delay_line[158];
                selected_coeff[5] = coeff_memory[96];
                selected_left[6] = delay_line[97];
                selected_right[6] = delay_line[157];
                selected_coeff[6] = coeff_memory[97];
                selected_left[7] = delay_line[98];
                selected_right[7] = delay_line[156];
                selected_coeff[7] = coeff_memory[98];
                selected_left[8] = delay_line[99];
                selected_right[8] = delay_line[155];
                selected_coeff[8] = coeff_memory[99];
                selected_left[9] = delay_line[100];
                selected_right[9] = delay_line[154];
                selected_coeff[9] = coeff_memory[100];
                selected_left[10] = delay_line[101];
                selected_right[10] = delay_line[153];
                selected_coeff[10] = coeff_memory[101];
                selected_left[11] = delay_line[102];
                selected_right[11] = delay_line[152];
                selected_coeff[11] = coeff_memory[102];
                selected_left[12] = delay_line[103];
                selected_right[12] = delay_line[151];
                selected_coeff[12] = coeff_memory[103];
            end
            4'd8: begin
                selected_left[0] = delay_line[104];
                selected_right[0] = delay_line[150];
                selected_coeff[0] = coeff_memory[104];
                selected_left[1] = delay_line[105];
                selected_right[1] = delay_line[149];
                selected_coeff[1] = coeff_memory[105];
                selected_left[2] = delay_line[106];
                selected_right[2] = delay_line[148];
                selected_coeff[2] = coeff_memory[106];
                selected_left[3] = delay_line[107];
                selected_right[3] = delay_line[147];
                selected_coeff[3] = coeff_memory[107];
                selected_left[4] = delay_line[108];
                selected_right[4] = delay_line[146];
                selected_coeff[4] = coeff_memory[108];
                selected_left[5] = delay_line[109];
                selected_right[5] = delay_line[145];
                selected_coeff[5] = coeff_memory[109];
                selected_left[6] = delay_line[110];
                selected_right[6] = delay_line[144];
                selected_coeff[6] = coeff_memory[110];
                selected_left[7] = delay_line[111];
                selected_right[7] = delay_line[143];
                selected_coeff[7] = coeff_memory[111];
                selected_left[8] = delay_line[112];
                selected_right[8] = delay_line[142];
                selected_coeff[8] = coeff_memory[112];
                selected_left[9] = delay_line[113];
                selected_right[9] = delay_line[141];
                selected_coeff[9] = coeff_memory[113];
                selected_left[10] = delay_line[114];
                selected_right[10] = delay_line[140];
                selected_coeff[10] = coeff_memory[114];
                selected_left[11] = delay_line[115];
                selected_right[11] = delay_line[139];
                selected_coeff[11] = coeff_memory[115];
                selected_left[12] = delay_line[116];
                selected_right[12] = delay_line[138];
                selected_coeff[12] = coeff_memory[116];
            end
            4'd9: begin
                selected_left[0] = delay_line[117];
                selected_right[0] = delay_line[137];
                selected_coeff[0] = coeff_memory[117];
                selected_left[1] = delay_line[118];
                selected_right[1] = delay_line[136];
                selected_coeff[1] = coeff_memory[118];
                selected_left[2] = delay_line[119];
                selected_right[2] = delay_line[135];
                selected_coeff[2] = coeff_memory[119];
                selected_left[3] = delay_line[120];
                selected_right[3] = delay_line[134];
                selected_coeff[3] = coeff_memory[120];
                selected_left[4] = delay_line[121];
                selected_right[4] = delay_line[133];
                selected_coeff[4] = coeff_memory[121];
                selected_left[5] = delay_line[122];
                selected_right[5] = delay_line[132];
                selected_coeff[5] = coeff_memory[122];
                selected_left[6] = delay_line[123];
                selected_right[6] = delay_line[131];
                selected_coeff[6] = coeff_memory[123];
                selected_left[7] = delay_line[124];
                selected_right[7] = delay_line[130];
                selected_coeff[7] = coeff_memory[124];
                selected_left[8] = delay_line[125];
                selected_right[8] = delay_line[129];
                selected_coeff[8] = coeff_memory[125];
                selected_left[9] = delay_line[126];
                selected_right[9] = delay_line[128];
                selected_coeff[9] = coeff_memory[126];
                selected_left[10] = delay_line[127];
                selected_coeff[10] = coeff_memory[127];
            end
            default: begin end
        endcase
    end

    function signed [OUTPUT_WIDTH-1:0] quantize_output;
        input signed [SUM_WIDTH-1:0] value;
        reg signed [SUM_WIDTH-1:0] rounded;
        begin
            rounded = value + ({{(SUM_WIDTH-1){1'b0}}, 1'b1} << (COEFF_FRACTION-1));
            quantize_output = rounded >>> COEFF_FRACTION;
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            for (initialize_index = 0; initialize_index < TAP_COUNT;
                    initialize_index = initialize_index+1)
                delay_line[initialize_index] <= {INPUT_WIDTH{1'b0}};
            active <= 1'b0;
            phase <= 4'd0;
            input_overrun <= 1'b0;
        end else begin
            if (sample_valid) begin
                for (shift_index = TAP_COUNT-1; shift_index > 0;
                        shift_index = shift_index-1)
                    delay_line[shift_index] <= delay_line[shift_index-1];
                delay_line[0] <= sample_data;
            end

            if (!active) begin
                if (sample_valid) begin
                    active <= 1'b1;
                    phase <= 4'd0;
                end
            end else if (phase == PHASES-1) begin
                if (sample_valid) begin
                    active <= 1'b1;
                    phase <= 4'd0;
                end else begin
                    active <= 1'b0;
                end
            end else begin
                if (sample_valid)
                    input_overrun <= 1'b1;
                phase <= phase+1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_select <= 1'b0;
            valid_pair <= 1'b0;
            valid_product <= 1'b0;
            valid_level1 <= 1'b0;
            valid_level2 <= 1'b0;
            valid_level3 <= 1'b0;
            valid_level4 <= 1'b0;
            valid_final <= 1'b0;
            tag_select <= 4'd0;
            tag_pair <= 4'd0;
            tag_product <= 4'd0;
            tag_level1 <= 4'd0;
            tag_level2 <= 4'd0;
            tag_level3 <= 4'd0;
            tag_level4 <= 4'd0;
            accumulator <= {SUM_WIDTH{1'b0}};
            final_sum <= {SUM_WIDTH{1'b0}};
            output_valid <= 1'b0;
            output_data <= {OUTPUT_WIDTH{1'b0}};
        end else begin
            for (product_lane = 0; product_lane < LANES; product_lane = product_lane+1) begin
                left_stage[product_lane] <= selected_left[product_lane];
                right_stage[product_lane] <= selected_right[product_lane];
                coeff_select_stage[product_lane] <= selected_coeff[product_lane];
                pair_stage[product_lane] <=
                    {left_stage[product_lane][INPUT_WIDTH-1], left_stage[product_lane]} +
                    {right_stage[product_lane][INPUT_WIDTH-1], right_stage[product_lane]};
                coeff_stage[product_lane] <= coeff_select_stage[product_lane];
                product_stage[product_lane] <= pair_stage[product_lane]*coeff_stage[product_lane];
            end
            valid_select <= active;
            tag_select <= phase;
            valid_pair <= valid_select;
            tag_pair <= tag_select;
            valid_product <= valid_pair;
            tag_product <= tag_pair;

            add_level1[0] <= {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[0][PRODUCT_WIDTH-1]}}, product_stage[0]} +
                             {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[1][PRODUCT_WIDTH-1]}}, product_stage[1]};
            add_level1[1] <= {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[2][PRODUCT_WIDTH-1]}}, product_stage[2]} +
                             {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[3][PRODUCT_WIDTH-1]}}, product_stage[3]};
            add_level1[2] <= {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[4][PRODUCT_WIDTH-1]}}, product_stage[4]} +
                             {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[5][PRODUCT_WIDTH-1]}}, product_stage[5]};
            add_level1[3] <= {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[6][PRODUCT_WIDTH-1]}}, product_stage[6]} +
                             {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[7][PRODUCT_WIDTH-1]}}, product_stage[7]};
            add_level1[4] <= {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[8][PRODUCT_WIDTH-1]}}, product_stage[8]} +
                             {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[9][PRODUCT_WIDTH-1]}}, product_stage[9]};
            add_level1[5] <= {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[10][PRODUCT_WIDTH-1]}}, product_stage[10]} +
                             {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[11][PRODUCT_WIDTH-1]}}, product_stage[11]};
            add_level1[6] <= {{(SUM_WIDTH-PRODUCT_WIDTH){product_stage[12][PRODUCT_WIDTH-1]}}, product_stage[12]};
            valid_level1 <= valid_product;
            tag_level1 <= tag_product;

            add_level2[0] <= add_level1[0]+add_level1[1];
            add_level2[1] <= add_level1[2]+add_level1[3];
            add_level2[2] <= add_level1[4]+add_level1[5];
            add_level2[3] <= add_level1[6];
            valid_level2 <= valid_level1;
            tag_level2 <= tag_level1;

            add_level3[0] <= add_level2[0]+add_level2[1];
            add_level3[1] <= add_level2[2]+add_level2[3];
            valid_level3 <= valid_level2;
            tag_level3 <= tag_level2;

            add_level4 <= add_level3[0]+add_level3[1];
            valid_level4 <= valid_level3;
            tag_level4 <= tag_level3;

            valid_final <= 1'b0;
            if (valid_level4) begin
                if (tag_level4 == 0)
                    accumulator <= add_level4;
                else
                    accumulator <= accumulator+add_level4;
                if (tag_level4 == PHASES-1) begin
                    final_sum <= accumulator+add_level4;
                    valid_final <= 1'b1;
                end
            end
            output_valid <= valid_final;
            if (valid_final)
                output_data <= quantize_output(final_sum);
        end
    end

endmodule
