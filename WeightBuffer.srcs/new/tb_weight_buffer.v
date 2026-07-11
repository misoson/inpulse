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
    
    reg write_en;
    reg [5:0] weight_addr;
    reg signed [DATA_WIDTH-1:0] weight_in;
    
    reg bias_write_en;
    reg [1:0] bias_addr;
    reg signed [31:0] bias_in;

    // 출력 와이어 (PE0 ~ PE3)
    wire signed [DATA_WIDTH-1:0] pe0_w0, pe0_w1, pe0_w2, pe0_w3, pe0_w4, pe0_w5, pe0_w6, pe0_w7, pe0_w8;
    wire signed [31:0] pe0_bias;
    
    wire signed [DATA_WIDTH-1:0] pe1_w0, pe1_w1, pe1_w2, pe1_w3, pe1_w4, pe1_w5, pe1_w6, pe1_w7, pe1_w8;
    wire signed [31:0] pe1_bias;
    
    wire signed [DATA_WIDTH-1:0] pe2_w0, pe2_w1, pe2_w2, pe2_w3, pe2_w4, pe2_w5, pe2_w6, pe2_w7, pe2_w8;
    wire signed [31:0] pe2_bias;
    
    wire signed [DATA_WIDTH-1:0] pe3_w0, pe3_w1, pe3_w2, pe3_w3, pe3_w4, pe3_w5, pe3_w6, pe3_w7, pe3_w8;
    wire signed [31:0] pe3_bias;

    // 테스트할 UUT (Unit Under Test) 인스턴스화
    weight_buffer #(
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk(clk),
        .reset(reset),
        
        .write_en(write_en),
        .weight_addr(weight_addr),
        .weight_in(weight_in),
        
        .bias_write_en(bias_write_en),
        .bias_addr(bias_addr),
        .bias_in(bias_in),
        
        // PE0
        .pe0_weight_0(pe0_w0), .pe0_weight_1(pe0_w1), .pe0_weight_2(pe0_w2),
        .pe0_weight_3(pe0_w3), .pe0_weight_4(pe0_w4), .pe0_weight_5(pe0_w5),
        .pe0_weight_6(pe0_w6), .pe0_weight_7(pe0_w7), .pe0_weight_8(pe0_w8),
        .pe0_bias(pe0_bias),
        
        // PE1
        .pe1_weight_0(pe1_w0), .pe1_weight_1(pe1_w1), .pe1_weight_2(pe1_w2),
        .pe1_weight_3(pe1_w3), .pe1_weight_4(pe1_w4), .pe1_weight_5(pe1_w5),
        .pe1_weight_6(pe1_w6), .pe1_weight_7(pe1_w7), .pe1_weight_8(pe1_w8),
        .pe1_bias(pe1_bias),
        
        // PE2
        .pe2_weight_0(pe2_w0), .pe2_weight_1(pe2_w1), .pe2_weight_2(pe2_w2),
        .pe2_weight_3(pe2_w3), .pe2_weight_4(pe2_w4), .pe2_weight_5(pe2_w5),
        .pe2_weight_6(pe2_w6), .pe2_weight_7(pe2_w7), .pe2_weight_8(pe2_w8),
        .pe2_bias(pe2_bias),
        
        // PE3
        .pe3_weight_0(pe3_w0), .pe3_weight_1(pe3_w1), .pe3_weight_2(pe3_w2),
        .pe3_weight_3(pe3_w3), .pe3_weight_4(pe3_w4), .pe3_weight_5(pe3_w5),
        .pe3_weight_6(pe3_w6), .pe3_weight_7(pe3_w7), .pe3_weight_8(pe3_w8),
        .pe3_bias(pe3_bias)
    );

    // 10ns 주기의 클럭 생성
    always #5 clk = ~clk;

    // 테스트 시나리오 시작
    integer i;
    initial begin
        // 1. 초기화
        clk = 0;
        reset = 1;
        write_en = 0;
        weight_addr = 0;
        weight_in = 0;
        bias_write_en = 0;
        bias_addr = 0;
        bias_in = 0;

        #20 reset = 0;
        #10;

        // 2. 가중치 36개 순차 쓰기 (Sequential Write)
        $display("[1] 가중치 데이터 적재 시작");
        write_en = 1;
        for (i = 0; i < 36; i = i + 1) begin
            weight_addr = i;
            weight_in = i + 10; // (예: 주소 0에는 10, 주소 35에는 45 입력)
            #10;
        end
        write_en = 0;

        // 3. 바이어스 4개 순차 쓰기 (Sequential Write)
        $display("[2] 바이어스 데이터 적재 시작");
        bias_write_en = 1;
        for (i = 0; i < 4; i = i + 1) begin
            bias_addr = i;
            bias_in = (i + 1) * 1000; // (예: 1000, 2000, 3000, 4000)
            #10;
        end
        bias_write_en = 0;

        // 약간 대기
        #20;

        // 4. 병렬 출력 결과 확인 (Parallel Read Check)
        $display("\n[3] 병렬 출력 결과 확인");
        
        $display("[PE0] W0:%0d, W1:%0d, W8:%0d | Bias:%0d", pe0_w0, pe0_w1, pe0_w8, pe0_bias);
        if (pe0_w0 == 10 && pe0_w8 == 18 && pe0_bias == 1000) $display(" -> PE0 통과!");
        else $display(" -> PE0 실패");

        $display("[PE1] W0:%0d, W1:%0d, W8:%0d | Bias:%0d", pe1_w0, pe1_w1, pe1_w8, pe1_bias);
        if (pe1_w0 == 19 && pe1_w8 == 27 && pe1_bias == 2000) $display(" -> PE1 통과!");
        else $display(" -> PE1 실패");

        $display("[PE2] W0:%0d, W1:%0d, W8:%0d | Bias:%0d", pe2_w0, pe2_w1, pe2_w8, pe2_bias);
        if (pe2_w0 == 28 && pe2_w8 == 36 && pe2_bias == 3000) $display(" -> PE2 통과!");
        else $display(" -> PE2 실패");

        $display("[PE3] W0:%0d, W1:%0d, W8:%0d | Bias:%0d", pe3_w0, pe3_w1, pe3_w8, pe3_bias);
        if (pe3_w0 == 37 && pe3_w8 == 45 && pe3_bias == 4000) $display(" -> PE3 통과!");
        else $display(" -> PE3 실패");

        $display("\n시뮬레이션 완료");
        $finish;
    end

endmodule
