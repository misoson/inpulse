`timescale 1ns / 1ps
//=============================================================================
// File        : pe.v (수정본)
//
// 변경 사항 (원본 대비):
//   - MAC 곱셈 9개(3x3 kernel)를 개별 wire로 분리하고
//     (* use_dsp = "yes" *) 속성을 부여하여 Vivado가 LUT 기반 곱셈기가 아닌
//     DSP48 슬라이스로 강제 매핑하도록 함.
//     -> Slice LUT 사용량 및 전력 절감 목적 (합성 리포트에서 Logic 53%,
//        DSP 3%로 나타났던 불균형 개선)
//   - shift-register / saturation / pipeline 로직은 원본과 동일
//=============================================================================

module pe #(
    parameter DATA_WIDTH  = 8,
    parameter LINE_LENGTH = 1024
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
    // 1. INPUT PART & Shift Registers (변경 없음)
    // =========================================================
    reg [DATA_WIDTH-1:0] row0_shift0, row0_shift1, row0_shift2;
    reg [DATA_WIDTH-1:0] row1_shift0, row1_shift1, row1_shift2;
    reg [DATA_WIDTH-1:0] row2_shift0, row2_shift1, row2_shift2;

    reg [DATA_WIDTH-1:0] pe_pixel_0, pe_pixel_1, pe_pixel_2;
    reg [DATA_WIDTH-1:0] pe_pixel_3, pe_pixel_4, pe_pixel_5;
    reg [DATA_WIDTH-1:0] pe_pixel_6, pe_pixel_7, pe_pixel_8;

    reg [$clog2(LINE_LENGTH)-1:0] column_count;
    reg                           input_valid_d;

    wire [DATA_WIDTH-1:0] line0_data, line1_data, line2_data;

    assign line0_data = mode_int4 ? { {(DATA_WIDTH-4){1'b0}}, line_out0[3:0] } : line_out0;
    assign line1_data = mode_int4 ? { {(DATA_WIDTH-4){1'b0}}, line_out1[3:0] } : line_out1;
    assign line2_data = mode_int4 ? { {(DATA_WIDTH-4){1'b0}}, line_out2[3:0] } : line_out2;

    // =========================================================
    // 2. MAC PART - DSP48 강제 매핑
    //
    //    기존에는 mul_pw() 함수 하나로 9번 곱셈을 인라인 처리했는데,
    //    이 경우 Vivado가 곱셈을 LUT 기반 조합 로직으로 합성하는 경우가
    //    흔합니다. 각 곱셈 결과를 별도 wire로 분리하고 use_dsp 속성을
    //    붙이면 DSP48로 매핑될 확률이 크게 높아집니다.
    // =========================================================
    function automatic signed [DATA_WIDTH:0] pixel_extend;
        input [DATA_WIDTH-1:0] pixel;
        input mode_int4_f;
        begin
            if (mode_int4_f)
                pixel_extend = {{(DATA_WIDTH-3){1'b0}}, pixel[3:0]};
            else
                pixel_extend = {1'b0, pixel};
        end
    endfunction

    function automatic signed [DATA_WIDTH-1:0] weight_extend;
        input signed [DATA_WIDTH-1:0] weight;
        input mode_int4_f;
        begin
            if (mode_int4_f)
                weight_extend = {{(DATA_WIDTH-4){weight[3]}}, weight[3:0]};
            else
                weight_extend = weight;
        end
    endfunction

    (* use_dsp = "yes" *) wire signed [31:0] mul0 = pixel_extend(pe_pixel_0, mode_int4) * weight_extend(weight_0, mode_int4);
    (* use_dsp = "yes" *) wire signed [31:0] mul1 = pixel_extend(pe_pixel_1, mode_int4) * weight_extend(weight_1, mode_int4);
    (* use_dsp = "yes" *) wire signed [31:0] mul2 = pixel_extend(pe_pixel_2, mode_int4) * weight_extend(weight_2, mode_int4);
    (* use_dsp = "yes" *) wire signed [31:0] mul3 = pixel_extend(pe_pixel_3, mode_int4) * weight_extend(weight_3, mode_int4);
    (* use_dsp = "yes" *) wire signed [31:0] mul4 = pixel_extend(pe_pixel_4, mode_int4) * weight_extend(weight_4, mode_int4);
    (* use_dsp = "yes" *) wire signed [31:0] mul5 = pixel_extend(pe_pixel_5, mode_int4) * weight_extend(weight_5, mode_int4);
    (* use_dsp = "yes" *) wire signed [31:0] mul6 = pixel_extend(pe_pixel_6, mode_int4) * weight_extend(weight_6, mode_int4);
    (* use_dsp = "yes" *) wire signed [31:0] mul7 = pixel_extend(pe_pixel_7, mode_int4) * weight_extend(weight_7, mode_int4);
    (* use_dsp = "yes" *) wire signed [31:0] mul8 = pixel_extend(pe_pixel_8, mode_int4) * weight_extend(weight_8, mode_int4);

    wire signed [31:0] mac_result_comb =
        mul0 + mul1 + mul2 + mul3 + mul4 + mul5 + mul6 + mul7 + mul8 + bias;

    reg signed [31:0] mac_result;
    reg               mac_valid;

    // =========================================================
    // 3. SATURATION & PIPELINE CONTROL (변경 없음)
    // =========================================================
    wire signed [31:0] target_max = mode_int4 ? 32'sd2047  : 32'sd524287;
    wire signed [31:0] target_min = mode_int4 ? -32'sd2047 : -32'sd524287;
    wire signed [31:0] saturated_result = (mac_result > target_max) ? target_max :
                                          (mac_result < target_min) ? target_min : mac_result;

    // =========================================================
    // 4. SEQUENTIAL PIPELINE (변경 없음)
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
