`timescale 1ns / 1ps

module pe (
    input wire clk,
    input wire rst_n,
    input wire mode_flag,        // 0: INT8 모드, 1: INT4 모드
    
    // 3-Line Buffer로부터 들어오는 픽셀 입력 9개
    input wire [7:0] pixel_in_1, input wire [7:0] pixel_in_2, input wire [7:0] pixel_in_3,
    input wire [7:0] pixel_in_4, input wire [7:0] pixel_in_5, input wire [7:0] pixel_in_6,
    input wire [7:0] pixel_in_7, input wire [7:0] pixel_in_8, input wire [7:0] pixel_in_9,
    
    // 가중치 메모리로부터 들어오는 웨이트 입력 9개
    input wire [7:0] weight_in_1, input wire [7:0] weight_in_2, input wire [7:0] weight_in_3,
    input wire [7:0] weight_in_4, input wire [7:0] weight_in_5, input wire [7:0] weight_in_6,
    input wire [7:0] weight_in_7, input wire [7:0] weight_in_8, input wire [7:0] weight_in_9,
    
    // 최종 MAC 연산 결과 출력 (Activation Unit으로 전달됨)
    output reg [23:0] mac_out
);

    // 곱셈기 결과와 가산기 트리를 연결할 와이어 선언
    wire [15:0] mul_out_1, mul_out_2, mul_out_3;
    wire [15:0] mul_out_4, mul_out_5, mul_out_6;
    wire [15:0] mul_out_7, mul_out_8, mul_out_9;
    
    wire [23:0] tree_to_reg;

    // =========================================================
    // 1. 가변 정밀도 곱셈기 9개 병렬 인스턴스화 (조립)
    // =========================================================
    var_mul u_mul_1 (.mode_flag(mode_flag), .a(pixel_in_1), .b(weight_in_1), .p(mul_out_1));
    var_mul u_mul_2 (.mode_flag(mode_flag), .a(pixel_in_2), .b(weight_in_2), .p(mul_out_2));
    var_mul u_mul_3 (.mode_flag(mode_flag), .a(pixel_in_3), .b(weight_in_3), .p(mul_out_3));
    var_mul u_mul_4 (.mode_flag(mode_flag), .a(pixel_in_4), .b(weight_in_4), .p(mul_out_4));
    var_mul u_mul_5 (.mode_flag(mode_flag), .a(pixel_in_5), .b(weight_in_5), .p(mul_out_5));
    var_mul u_mul_6 (.mode_flag(mode_flag), .a(pixel_in_6), .b(weight_in_6), .p(mul_out_6));
    var_mul u_mul_7 (.mode_flag(mode_flag), .a(pixel_in_7), .b(weight_in_7), .p(mul_out_7));
    var_mul u_mul_8 (.mode_flag(mode_flag), .a(pixel_in_8), .b(weight_in_8), .p(mul_out_8));
    var_mul u_mul_9 (.mode_flag(mode_flag), .a(pixel_in_9), .b(weight_in_9), .p(mul_out_9));

    // =========================================================
    // 2. 가산기 트리 인스턴스화 (조립)
    // =========================================================
    adder_tree u_adder_tree (
        .mode_flag(mode_flag),
        .m1(mul_out_1), .m2(mul_out_2), .m3(mul_out_3),
        .m4(mul_out_4), .m5(mul_out_5), .m6(mul_out_6),
        .m7(mul_out_7), .m8(mul_out_8), .m9(mul_out_9),
        .sum_out(tree_to_reg)
    );

    // =========================================================
    // 3. 출력 파이프라인 레지스터 (타이밍 마진 최적화 및 안정화)
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_out <= 24'd0;
        end else begin
            mac_out <= tree_to_reg;
        end
    end

endmodule