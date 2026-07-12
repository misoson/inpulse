`timescale 1ns / 1ps

module pe #(
    parameter DATA_WIDTH  = 8,
    parameter LINE_LENGTH = 1024  // 1) LINE_LENGTH 파라미터 유지
)(
    input  wire clk,
    input  wire reset,        // active-high reset
    input  wire mode_int4,    // 0: INT8, 1: INT4

    // from line_buffer
    input  wire                  in_valid,
    input  wire [DATA_WIDTH-1:0] line_out0,
    input  wire [DATA_WIDTH-1:0] line_out1,
    input  wire [DATA_WIDTH-1:0] line_out2,

    // 3x3 kernel weights
    input  wire signed [DATA_WIDTH-1:0] weight_0, weight_1, weight_2,
    input  wire signed [DATA_WIDTH-1:0] weight_3, weight_4, weight_5,
    input  wire signed [DATA_WIDTH-1:0] weight_6, weight_7, weight_8,
    input  wire signed [31:0]           bias,

    // to activation_unit
    output reg signed [31:0] conv_out,
    output reg               valid_out
);

    // =========================================================
    // 1. INPUT PART & Shift Registers
    // =========================================================
    reg [DATA_WIDTH-1:0] row0_shift0, row0_shift1, row0_shift2;
    reg [DATA_WIDTH-1:0] row1_shift0, row1_shift1, row1_shift2;
    reg [DATA_WIDTH-1:0] row2_shift0, row2_shift1, row2_shift2;

    reg [DATA_WIDTH-1:0] pe_pixel_0, pe_pixel_1, pe_pixel_2;
    reg [DATA_WIDTH-1:0] pe_pixel_3, pe_pixel_4, pe_pixel_5;
    reg [DATA_WIDTH-1:0] pe_pixel_6, pe_pixel_7, pe_pixel_8;

    // 2) 일반화된 비트 폭의 column_count 사용 (valid_count는 제거됨)
    reg [$clog2(LINE_LENGTH)-1:0] column_count;
    reg                           input_valid_d;

    wire [DATA_WIDTH-1:0] line0_data, line1_data, line2_data;

    assign line0_data = mode_int4 ? { {(DATA_WIDTH-4){1'b0}}, line_out0[3:0] } : line_out0;
    assign line1_data = mode_int4 ? { {(DATA_WIDTH-4){1'b0}}, line_out1[3:0] } : line_out1;
    assign line2_data = mode_int4 ? { {(DATA_WIDTH-4){1'b0}}, line_out2[3:0] } : line_out2;

    // =========================================================
    // 2. MAC PART (INT8 / INT4 Multiplier Function)
    // =========================================================
    function signed [31:0] mul_pw;
        input [DATA_WIDTH-1:0] pixel;
        input signed [DATA_WIDTH-1:0] weight;
        input mode_int4_f;
        reg signed [DATA_WIDTH:0] pixel_ext;
        reg signed [DATA_WIDTH-1:0] weight_ext;
        begin
            if (mode_int4_f) begin
                pixel_ext  = {{(DATA_WIDTH-3){1'b0}}, pixel[3:0]};
                weight_ext = {{(DATA_WIDTH-4){weight[3]}}, weight[3:0]};
            end else begin
                pixel_ext  = {1'b0, pixel};
                weight_ext = weight;
            end
            mul_pw = pixel_ext * weight_ext;
        end
    endfunction

    wire signed [31:0] mac_result_comb;
    assign mac_result_comb =
        mul_pw(pe_pixel_0, weight_0, mode_int4) + mul_pw(pe_pixel_1, weight_1, mode_int4) + mul_pw(pe_pixel_2, weight_2, mode_int4) +
        mul_pw(pe_pixel_3, weight_3, mode_int4) + mul_pw(pe_pixel_4, weight_4, mode_int4) + mul_pw(pe_pixel_5, weight_5, mode_int4) +
        mul_pw(pe_pixel_6, weight_6, mode_int4) + mul_pw(pe_pixel_7, weight_7, mode_int4) + mul_pw(pe_pixel_8, weight_8, mode_int4) + bias;

    reg signed [31:0] mac_result;
    reg               mac_valid;

    // =========================================================
    // 3. SATURATION & PIPELINE CONTROL
    // =========================================================
    wire signed [31:0] target_max = mode_int4 ? 32'sd2047  : 32'sd524287;
    wire signed [31:0] target_min = mode_int4 ? -32'sd2047 : -32'sd524287;
    wire signed [31:0] saturated_result = (mac_result > target_max) ? target_max :
                                          (mac_result < target_min) ? target_min : mac_result;

    // =========================================================
    // 4. SEQUENTIAL PIPELINE
    // =========================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            row0_shift0 <= 0; row0_shift1 <= 0; row0_shift2 <= 0;
            row1_shift0 <= 0; row1_shift1 <= 0; row1_shift2 <= 0;
            row2_shift0 <= 0; row2_shift1 <= 0; row2_shift2 <= 0;

            pe_pixel_0 <= 0; pe_pixel_1 <= 0; pe_pixel_2 <= 0;
            pe_pixel_3 <= 0; pe_pixel_4 <= 0; pe_pixel_5 <= 0;
            pe_pixel_6 <= 0; pe_pixel_7 <= 0; pe_pixel_8 <= 0;

            column_count  <= 0;
            input_valid_d <= 1'b0;
            mac_result    <= 32'sd0;
            mac_valid     <= 1'b0;
            conv_out      <= 32'sd0;
            valid_out     <= 1'b0;
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

                pe_pixel_0 <= row0_shift2;
                pe_pixel_1 <= row0_shift1;
                pe_pixel_2 <= row0_shift0;

                pe_pixel_3 <= row1_shift2;
                pe_pixel_4 <= row1_shift1;
                pe_pixel_5 <= row1_shift0;

                pe_pixel_6 <= row2_shift2;
                pe_pixel_7 <= row2_shift1;
                pe_pixel_8 <= row2_shift0;

                // valid 생성 (각 행의 첫 두 열에서는 valid 차단)
                if (column_count >= 2)
                    input_valid_d <= 1'b1;
                else
                    input_valid_d <= 1'b0;

                // column 관리 및 행 끝(End-of-Row) 검사 및 다음 행 준비 초기화
                if (column_count == LINE_LENGTH - 1) begin
                    column_count <= 0;

                    row0_shift0 <= 0; row0_shift1 <= 0; row0_shift2 <= 0;
                    row1_shift0 <= 0; row1_shift1 <= 0; row1_shift2 <= 0;
                    row2_shift0 <= 0; row2_shift1 <= 0; row2_shift2 <= 0;

                    // ❗ 수정 완료: 마지막 픽셀 윈도우 유효성을 살리기 위해 input_valid_d <= 1'b0; 삭제
                end 
                else begin
                    column_count <= column_count + 1'b1;
                end
            end 
            else begin
                input_valid_d <= 1'b0;
            end

            // MAC pipeline register
            if (input_valid_d) begin
                mac_result <= mac_result_comb;
                mac_valid  <= 1'b1;
            end 
            else begin
                mac_valid <= 1'b0;
            end

            // CTRL output register
            conv_out  <= saturated_result;
            valid_out <= mac_valid;
        end
    end

endmodule