`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/11 10:35:24
// Design Name: 
// Module Name: weight_buffer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module weight_buffer #(
    parameter DATA_WIDTH = 8
)(
    input  wire clk,
    input  wire reset,

    // 외부(Testbench 또는 AXI)에서 가중치를 입력하는 포트 (32-bit Bus)
    input  wire        wr_en,       // 쓰기 활성화 신호
    input  wire [3:0]  wr_addr,     // 0~15까지의 주소
    input  wire [31:0] wr_data,     // 32비트 입력 데이터

    // PE0 출력
    output wire signed [DATA_WIDTH-1:0] pe0_weight_0, pe0_weight_1, pe0_weight_2, pe0_weight_3,
    output wire signed [DATA_WIDTH-1:0] pe0_weight_4, pe0_weight_5, pe0_weight_6, pe0_weight_7,
    output wire signed [DATA_WIDTH-1:0] pe0_weight_8,
    output wire signed [31:0]           pe0_bias,

    // PE1 출력
    output wire signed [DATA_WIDTH-1:0] pe1_weight_0, pe1_weight_1, pe1_weight_2, pe1_weight_3,
    output wire signed [DATA_WIDTH-1:0] pe1_weight_4, pe1_weight_5, pe1_weight_6, pe1_weight_7,
    output wire signed [DATA_WIDTH-1:0] pe1_weight_8,
    output wire signed [31:0]           pe1_bias,

    // PE2 출력
    output wire signed [DATA_WIDTH-1:0] pe2_weight_0, pe2_weight_1, pe2_weight_2, pe2_weight_3,
    output wire signed [DATA_WIDTH-1:0] pe2_weight_4, pe2_weight_5, pe2_weight_6, pe2_weight_7,
    output wire signed [DATA_WIDTH-1:0] pe2_weight_8,
    output wire signed [31:0]           pe2_bias,

    // PE3 출력
    output wire signed [DATA_WIDTH-1:0] pe3_weight_0, pe3_weight_1, pe3_weight_2, pe3_weight_3,
    output wire signed [DATA_WIDTH-1:0] pe3_weight_4, pe3_weight_5, pe3_weight_6, pe3_weight_7,
    output wire signed [DATA_WIDTH-1:0] pe3_weight_8,
    output wire signed [31:0]           pe3_bias
);

    // 16개의 32비트 레지스터(메모리) 선언
    reg [31:0] mem [0:15];
    integer i;

    // 쓰기 동작 (Write)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 16; i = i + 1) begin
                mem[i] <= 32'd0;
            end
        end
        else if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end

    // 읽기 동작 (연속 할당 - Constant Read)
    // 메모리에 저장된 값을 8비트씩 쪼개서 각 PE의 포트로 항상 출력합니다.
    
    // PE0 할당 (주소 0~3)
    assign pe0_weight_0 = mem[0][7:0];   assign pe0_weight_1 = mem[0][15:8];
    assign pe0_weight_2 = mem[0][23:16]; assign pe0_weight_3 = mem[0][31:24];
    assign pe0_weight_4 = mem[1][7:0];   assign pe0_weight_5 = mem[1][15:8];
    assign pe0_weight_6 = mem[1][23:16]; assign pe0_weight_7 = mem[1][31:24];
    assign pe0_weight_8 = mem[2][7:0];
    assign pe0_bias     = mem[3];

    // PE1 할당 (주소 4~7)
    assign pe1_weight_0 = mem[4][7:0];   assign pe1_weight_1 = mem[4][15:8];
    assign pe1_weight_2 = mem[4][23:16]; assign pe1_weight_3 = mem[4][31:24];
    assign pe1_weight_4 = mem[5][7:0];   assign pe1_weight_5 = mem[5][15:8];
    assign pe1_weight_6 = mem[5][23:16]; assign pe1_weight_7 = mem[5][31:24];
    assign pe1_weight_8 = mem[6][7:0];
    assign pe1_bias     = mem[7];

    // PE2 할당 (주소 8~11)
    assign pe2_weight_0 = mem[8][7:0];   assign pe2_weight_1 = mem[8][15:8];
    assign pe2_weight_2 = mem[8][23:16]; assign pe2_weight_3 = mem[8][31:24];
    assign pe2_weight_4 = mem[9][7:0];   assign pe2_weight_5 = mem[9][15:8];
    assign pe2_weight_6 = mem[9][23:16]; assign pe2_weight_7 = mem[9][31:24];
    assign pe2_weight_8 = mem[10][7:0];
    assign pe2_bias     = mem[11];

    // PE3 할당 (주소 12~15)
    assign pe3_weight_0 = mem[12][7:0];   assign pe3_weight_1 = mem[12][15:8];
    assign pe3_weight_2 = mem[12][23:16]; assign pe3_weight_3 = mem[12][31:24];
    assign pe3_weight_4 = mem[13][7:0];   assign pe3_weight_5 = mem[13][15:8];
    assign pe3_weight_6 = mem[13][23:16]; assign pe3_weight_7 = mem[13][31:24];
    assign pe3_weight_8 = mem[14][7:0];
    assign pe3_bias     = mem[15];

endmodule
