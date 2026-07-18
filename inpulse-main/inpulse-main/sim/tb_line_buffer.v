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

module tb_line_buffer();

    // 1. 시뮬레이션을 위해 파라미터 축소 (한 줄을 10픽셀로 가정)
    parameter DATA_WIDTH = 8;
    parameter LINE_LENGTH = 10;

    // 2. 입력 신호는 reg, 출력 신호는 wire로 선언
    reg clk;
    reg reset;
    reg photo_data_valid;
    reg [DATA_WIDTH-1:0] pixel_data_in;

    wire line_data_valid;
    wire [DATA_WIDTH-1:0] line_out0;
    wire [DATA_WIDTH-1:0] line_out1;
    wire [DATA_WIDTH-1:0] line_out2;

    // 3. 테스트할 모듈(UUT: Unit Under Test) 연결
    line_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .LINE_LENGTH(LINE_LENGTH) // 모듈의 640을 10으로 덮어씌움
    ) u_line_buffer (
        .clk(clk),
        .reset(reset),
        .photo_data_valid(photo_data_valid),
        .pixel_data_in(pixel_data_in),    // 이름이 변경된 포트 매핑
        .line_data_valid(line_data_valid),
        .line_out0(line_out0),
        .line_out1(line_out1),
        .line_out2(line_out2)
    );

    // 4. 클럭 생성 (10ns 주기 -> 100MHz)
    always #5 clk = ~clk;

    integer i;

    // 5. 실제 테스트 시나리오 작성
    initial begin
        // --- [초기화 상태] ---
        clk = 0;
        reset = 1;
        photo_data_valid = 0;
        pixel_data_in = 0;

        // 20ns 대기 후 리셋 해제 (정상 동작 시작)
        #20;
        reset = 0;
        #10;

        // --- [사진 데이터 연속 입력 시나리오] ---
        photo_data_valid = 1;
        
        // 총 4줄(LINE_LENGTH * 4 = 40픽셀) 분량의 데이터를 끊임없이 밀어넣음
        // 파형에서 추적하기 쉽도록 픽셀 값에 0, 1, 2, 3... 순서대로 숫자를 넣습니다.
        for (i = 0; i < LINE_LENGTH * 4; i = i + 1) begin
            pixel_data_in = i; 
            #10; // 1 클럭(10ns) 대기 후 다음 픽셀로 넘어감
        end

        // --- [데이터 입력 종료] ---
        photo_data_valid = 0;
        pixel_data_in = 0;
        
        // 50ns 동안 여운을 두고 관찰
        #50;
        
        // 시뮬레이션 완전 종료
        $finish;
    end

endmodule