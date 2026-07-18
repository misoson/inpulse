`timescale 1ns / 1ps

module line_buffer #(
    parameter DATA_WIDTH = 8,       // 단일 사진의 픽셀 비트 수 (예: 8-bit Gray)
    parameter LINE_LENGTH = 1024     // 사진의 가로 해상도 (예: VGA 640)
)(
    input  wire clk,
    input  wire reset,              // Active-high 리셋

    // 사진 데이터를 연속적으로 받는 인터페이스
    input  wire photo_data_valid,   // 사진 데이터가 입력 중일 때 1
    input  wire [DATA_WIDTH-1:0] pixel_data_in,
    
    output reg  line_data_valid,    // 3개 라인의 데이터가 모두 채워져 유효할 때 1
    output reg  [DATA_WIDTH-1:0] line_out0, // 현재 라인 (0 Line 지연)
    output reg  [DATA_WIDTH-1:0] line_out1, // 이전 라인 (1 Line 지연)
    output reg  [DATA_WIDTH-1:0] line_out2  // 전전 라인 (2 Line 지연)
);

    // 2개의 라인을 저장할 메모리 배열
    reg [DATA_WIDTH-1:0] ram_0 [0:LINE_LENGTH-1];
    reg [DATA_WIDTH-1:0] ram_1 [0:LINE_LENGTH-1];
    
    // 메모리 주소를 가리킬 포인터
    reg [$clog2(LINE_LENGTH)-1:0] ptr;
    
    // 버퍼가 2라인 이상 채워졌는지 확인하기 위한 라인 카운터
    reg [2:0] line_cnt;

    // [최적화 핵심] 메모리 쓰기 동작은 Reset 조건 없이 순수하게 클럭에만 동기화합니다.
    // 이렇게 해야 Vivado가 레지스터를 낭비하지 않고 내부 전용 BRAM으로 깔끔하게 매핑합니다.
    always @(posedge clk) begin
        if (photo_data_valid) begin
            ram_0[ptr] <= pixel_data_in;
            ram_1[ptr] <= ram_0[ptr];
        end
    end

    // 나머지 제어 로직 및 출력은 기존처럼 리셋을 포함하여 안전하게 관리합니다.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ptr       <= 0;
            line_cnt  <= 0;
            line_data_valid <= 1'b0;
            line_out0 <= 0;
            line_out1 <= 0;
            line_out2 <= 0;
        end 
        else if (photo_data_valid) begin
            // 출력
            line_out0 <= pixel_data_in;  
            line_out1 <= ram_0[ptr];     
            line_out2 <= ram_1[ptr];     
            
            // 포인터 및 라인 카운터 로직
            if (ptr == LINE_LENGTH - 1) begin
                ptr <= 0;
                if (line_cnt < 3'd3) begin
                    line_cnt <= line_cnt + 1; 
                end
            end else begin
                ptr <= ptr + 1;
            end
            
            // 유효성 검사
            if (line_cnt >= 3'd2) begin
                line_data_valid <= 1'b1;
            end else begin
                line_data_valid <= 1'b0;
            end
        end 
        else begin
            line_data_valid <= 1'b0;
        end
    end

endmodule
