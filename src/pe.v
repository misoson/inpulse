`timescale 1ns / 1ps

module pe #(
    parameter DATA_WIDTH = 8
)(
    input  wire clk,
    input  wire reset,        // Active-high reset
    input  wire mode_int4,    // 1: INT4, 0: INT8

    // from line_buffer
    input  wire in_valid,
    input  wire [DATA_WIDTH-1:0] line_out0,
    input  wire [DATA_WIDTH-1:0] line_out1,
    input  wire [DATA_WIDTH-1:0] line_out2,

    // weights
    input  wire signed [DATA_WIDTH-1:0] weight_0,
    input  wire signed [DATA_WIDTH-1:0] weight_1,
    input  wire signed [DATA_WIDTH-1:0] weight_2,
    input  wire signed [DATA_WIDTH-1:0] weight_3,
    input  wire signed [DATA_WIDTH-1:0] weight_4,
    input  wire signed [DATA_WIDTH-1:0] weight_5,
    input  wire signed [DATA_WIDTH-1:0] weight_6,
    input  wire signed [DATA_WIDTH-1:0] weight_7,
    input  wire signed [DATA_WIDTH-1:0] weight_8,

    input  wire signed [31:0] bias,

    // to activation_unit
    output reg signed [31:0] conv_out,
    output reg valid_out
);

    // =========================================================
    // 1. 입력부: pe_input 기능
    // line_buffer의 3-line 출력을 3x3 window로 변환
    // =========================================================

    reg [DATA_WIDTH-1:0] row0_shift0, row0_shift1, row0_shift2;
    reg [DATA_WIDTH-1:0] row1_shift0, row1_shift1, row1_shift2;
    reg [DATA_WIDTH-1:0] row2_shift0, row2_shift1, row2_shift2;

    reg [DATA_WIDTH-1:0] pe_pixel_0;
    reg [DATA_WIDTH-1:0] pe_pixel_1;
    reg [DATA_WIDTH-1:0] pe_pixel_2;
    reg [DATA_WIDTH-1:0] pe_pixel_3;
    reg [DATA_WIDTH-1:0] pe_pixel_4;
    reg [DATA_WIDTH-1:0] pe_pixel_5;
    reg [DATA_WIDTH-1:0] pe_pixel_6;
    reg [DATA_WIDTH-1:0] pe_pixel_7;
    reg [DATA_WIDTH-1:0] pe_pixel_8;

    reg [1:0] valid_count;
    reg pe_in_valid;

    wire [DATA_WIDTH-1:0] line0_data;
    wire [DATA_WIDTH-1:0] line1_data;
    wire [DATA_WIDTH-1:0] line2_data;

    assign line0_data = mode_int4 ? { {(DATA_WIDTH-4){1'b0}}, line_out0[3:0] } : line_out0;
    assign line1_data = mode_int4 ? { {(DATA_WIDTH-4){1'b0}}, line_out1[3:0] } : line_out1;
    assign line2_data = mode_int4 ? { {(DATA_WIDTH-4){1'b0}}, line_out2[3:0] } : line_out2;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            row0_shift0 <= 0; row0_shift1 <= 0; row0_shift2 <= 0;
            row1_shift0 <= 0; row1_shift1 <= 0; row1_shift2 <= 0;
            row2_shift0 <= 0; row2_shift1 <= 0; row2_shift2 <= 0;

            pe_pixel_0 <= 0; pe_pixel_1 <= 0; pe_pixel_2 <= 0;
            pe_pixel_3 <= 0; pe_pixel_4 <= 0; pe_pixel_5 <= 0;
            pe_pixel_6 <= 0; pe_pixel_7 <= 0; pe_pixel_8 <= 0;

            valid_count <= 2'd0;
            pe_in_valid <= 1'b0;
        end
        else begin
            if (in_valid) begin
                row0_shift2 <= row0_shift1;
                row0_shift1 <= row0_shift0;
                row0_shift0 <= line0_data;

                row1_shift2 <= row1_shift1;
                row1_shift1 <= row1_shift0;
                row1_shift0 <= line1_data;

                row2_shift2 <= row2_shift1;
                row2_shift1 <= row2_shift0;
                row2_shift0 <= line2_data;

                if (valid_count < 2'd2) begin
                    valid_count <= valid_count + 1'b1;
                    pe_in_valid <= 1'b0;
                end
                else begin
                    pe_in_valid <= 1'b1;
                end

                pe_pixel_0 <= row0_shift2;
                pe_pixel_1 <= row0_shift1;
                pe_pixel_2 <= row0_shift0;

                pe_pixel_3 <= row1_shift2;
                pe_pixel_4 <= row1_shift1;
                pe_pixel_5 <= row1_shift0;

                pe_pixel_6 <= row2_shift2;
                pe_pixel_7 <= row2_shift1;
                pe_pixel_8 <= row2_shift0;
            end
            else begin
                pe_in_valid <= 1'b0;
            end
        end
    end

    // =========================================================
    // 2. 연산부: 3x3 MAC
    // Conv = pixel*weight 9개 합 + bias
    // =========================================================

    function signed [31:0] pixel_ext;
        input [DATA_WIDTH-1:0] x;
        begin
            pixel_ext = mode_int4 ? $signed({28'b0, x[3:0]}) :
                                    $signed({24'b0, x[7:0]});
        end
    endfunction

    function signed [31:0] weight_ext;
        input signed [DATA_WIDTH-1:0] w;
        begin
            weight_ext = mode_int4 ? $signed({{28{w[3]}}, w[3:0]}) :
                                     $signed({{24{w[7]}}, w[7:0]});
        end
    endfunction

    wire signed [31:0] mac_sum;

    assign mac_sum =
        pixel_ext(pe_pixel_0) * weight_ext(weight_0) +
        pixel_ext(pe_pixel_1) * weight_ext(weight_1) +
        pixel_ext(pe_pixel_2) * weight_ext(weight_2) +
        pixel_ext(pe_pixel_3) * weight_ext(weight_3) +
        pixel_ext(pe_pixel_4) * weight_ext(weight_4) +
        pixel_ext(pe_pixel_5) * weight_ext(weight_5) +
        pixel_ext(pe_pixel_6) * weight_ext(weight_6) +
        pixel_ext(pe_pixel_7) * weight_ext(weight_7) +
        pixel_ext(pe_pixel_8) * weight_ext(weight_8) +
        bias;

    reg signed [31:0] mac_result;
    reg valid_d;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mac_result <= 32'sd0;
            valid_d    <= 1'b0;
        end
        else begin
            mac_result <= mac_sum;
            valid_d    <= pe_in_valid;
        end
    end

    // =========================================================
    // 3. 제어부/출력부: pe_ctrl 기능
    // saturation + valid_out 생성
    // =========================================================

    wire signed [31:0] target_max;
    wire signed [31:0] target_min;

    assign target_max = mode_int4 ? 32'sd2047 : 32'sd524287;
    assign target_min = mode_int4 ? -32'sd2047 : -32'sd524287;

    wire signed [31:0] saturated_result;

    assign saturated_result = (mac_result > target_max) ? target_max :
                              (mac_result < target_min) ? target_min :
                              mac_result;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            conv_out  <= 32'sd0;
            valid_out <= 1'b0;
        end
        else begin
            conv_out  <= saturated_result;
            valid_out <= valid_d;
        end
    end

endmodule