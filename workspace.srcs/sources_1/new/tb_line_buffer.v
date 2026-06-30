`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/27 10:24:42
// Design Name: 
// Module Name: tb_line_buffer
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

// 1. 테스트벤치 자체의 코드 괄호는 완전히 비워둡니다.
module tb_line_buffer();

    // 2. 테스트벤치 내부에서 신호를 제어할 변수 선언
    // (진짜 부품의 input으로 들어갈 선은 reg, output에서 나올 선은 wire)
    reg clk;
    reg reset;
    reg [7:0] pixel_data_in;
    
    wire [7:0] line_out0;
    wire [7:0] line_out1;
    wire [7:0] line_out2;

    // 3. 진짜 라인 버퍼 모듈(DUT)을 불러와서 선 연결하기
    line_buffer u_line_buffer (
        .clk(clk),
        .reset(reset),
        .pixel_data_in(pixel_data_in),
        .line_out0(line_out0),
        .line_out1(line_out1),
        .line_out2(line_out2)
    );

    // 4. 가상 클럭 및 시뮬레이션 자극(Stimulus) 인가 로직
    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        pixel_data_in = 0;
        #20;
        
        reset = 0;

        // 매 클럭마다 가짜 데이터 1, 2, 3... 넣어보기
        repeat(20) begin
            @(posedge clk);
            pixel_data_in = pixel_data_in + 1;
        end

        #100;
        $stop;
    end

endmodule
