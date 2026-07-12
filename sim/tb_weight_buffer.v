`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/11 12:04:41
// Design Name: 
// Module Name: tb_weight_buffer
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


module tb_weight_buffer;

    parameter DATA_WIDTH = 8;

    // 입력 레지스터 (Testbench에서 제어)
    reg clk;
    reg reset;
    
    reg        wr_en;
    reg [3:0]  wr_addr;
    reg [31:0] wr_data;

    // 출력 와이어 (PE0 ~ PE3)
    wire signed [DATA_WIDTH-1:0] pe0_w0, pe0_w1, pe0_w2, pe0_w3, pe0_w4, pe0_w5, pe0_w6, pe0_w7, pe0_w8;
    wire signed [31:0] pe0_bias;
    
    wire signed [DATA_WIDTH-1:0] pe1_w0, pe1_w1, pe1_w2, pe1_w3, pe1_w4, pe1_w5, pe1_w6, pe1_w7, pe1_w8;
    wire signed [31:0] pe1_bias;
    
    wire signed [DATA_WIDTH-1:0] pe2_w0, pe2_w1, pe2_w2, pe2_w3, pe2_w4, pe2_w5, pe2_w6, pe2_w7, pe2_w8;
    wire signed [31:0] pe2_bias;
    
    wire signed [DATA_WIDTH-1:0] pe3_w0, pe3_w1, pe3_w2, pe3_w3, pe3_w4, pe3_w5, pe3_w6, pe3_w7, pe3_w8;
    wire signed [31:0] pe3_bias;

    // 테스트할 UUT 인스턴스화
    weight_buffer #(
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk(clk),
        .reset(reset),
        
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        
        // PE0
        .pe0_weight_0(pe0_w0), .pe0_weight_1(pe0_w1), .pe0_weight_2(pe0_w2), .pe0_weight_3(pe0_w3),
        .pe0_weight_4(pe0_w4), .pe0_weight_5(pe0_w5), .pe0_weight_6(pe0_w6), .pe0_weight_7(pe0_w7),
        .pe0_weight_8(pe0_w8), .pe0_bias(pe0_bias),
        
        // PE1
        .pe1_weight_0(pe1_w0), .pe1_weight_1(pe1_w1), .pe1_weight_2(pe1_w2), .pe1_weight_3(pe1_w3),
        .pe1_weight_4(pe1_w4), .pe1_weight_5(pe1_w5), .pe1_weight_6(pe1_w6), .pe1_weight_7(pe1_w7),
        .pe1_weight_8(pe1_w8), .pe1_bias(pe1_bias),
        
        // PE2
        .pe2_weight_0(pe2_w0), .pe2_weight_1(pe2_w1), .pe2_weight_2(pe2_w2), .pe2_weight_3(pe2_w3),
        .pe2_weight_4(pe2_w4), .pe2_weight_5(pe2_w5), .pe2_weight_6(pe2_w6), .pe2_weight_7(pe2_w7),
        .pe2_weight_8(pe2_w8), .pe2_bias(pe2_bias),
        
        // PE3
        .pe3_weight_0(pe3_w0), .pe3_weight_1(pe3_w1), .pe3_weight_2(pe3_w2), .pe3_weight_3(pe3_w3),
        .pe3_weight_4(pe3_w4), .pe3_weight_5(pe3_w5), .pe3_weight_6(pe3_w6), .pe3_weight_7(pe3_w7),
        .pe3_weight_8(pe3_w8), .pe3_bias(pe3_bias)
    );

    // 10ns 주기의 클럭 생성
    always #5 clk = ~clk;

    initial begin
        // 1. 초기화
        clk = 0;
        reset = 1;
        wr_en = 0;
        wr_addr = 0;
        wr_data = 0;

        #20 reset = 0;
        #10;

        // 2. 가중치 및 바이어스 적재 시작 (PE0 기준)
        $display("--- [1] 32비트 패킹 데이터 적재 시작 ---");
        wr_en = 1;
        
        // PE0 데이터 (주소 0 ~ 3)
        // mem[0] = {W3, W2, W1, W0} -> {4, 3, 2, 1}
        wr_addr = 4'd0; wr_data = {8'd4, 8'd3, 8'd2, 8'd1}; #10;
        // mem[1] = {W7, W6, W5, W4} -> {8, 7, 6, 5}
        wr_addr = 4'd1; wr_data = {8'd8, 8'd7, 8'd6, 8'd5}; #10;
        // mem[2] = {X, X, X, W8} -> 하위 8비트만 W8로 들어감 (9)
        wr_addr = 4'd2; wr_data = {24'd0, 8'd9}; #10;
        // mem[3] = PE0 Bias (32비트 전체) -> 1000
        wr_addr = 4'd3; wr_data = 32'd1000; #10;
        
        // PE1 데이터 (주소 4 ~ 7) - 테스트용 임의 값
        wr_addr = 4'd4; wr_data = {8'd14, 8'd13, 8'd12, 8'd11}; #10;
        wr_addr = 4'd5; wr_data = {8'd18, 8'd17, 8'd16, 8'd15}; #10;
        wr_addr = 4'd6; wr_data = {24'd0, 8'd19}; #10;
        wr_addr = 4'd7; wr_data = 32'd2000; #10;

        wr_en = 0;
        #20;

        // 3. 언패킹(Unpacking) 병렬 출력 결과 확인
        $display("\n--- [2] 병렬 출력 결과 확인 ---");
        
        $display("[PE0] W0:%0d, W3:%0d, W4:%0d, W8:%0d | Bias:%0d", pe0_w0, pe0_w3, pe0_w4, pe0_w8, pe0_bias);
        if (pe0_w0 == 1 && pe0_w3 == 4 && pe0_w8 == 9 && pe0_bias == 1000) $display(" -> PE0 통과!");
        else $display(" -> PE0 실패...");

        $display("[PE1] W0:%0d, W3:%0d, W4:%0d, W8:%0d | Bias:%0d", pe1_w0, pe1_w3, pe1_w4, pe1_w8, pe1_bias);
        if (pe1_w0 == 11 && pe1_w3 == 14 && pe1_w8 == 19 && pe1_bias == 2000) $display(" -> PE1 통과!");
        else $display(" -> PE1 실패...");

        $display("\n시뮬레이션 완료!");
        $finish;
    end

endmodule
