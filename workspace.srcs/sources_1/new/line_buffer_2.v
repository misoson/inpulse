`timescale 1ns / 1ps

module line_buffer #(
    parameter DATA_WIDTH = 8,       // 픽셀 데이터 비트 폭 (예: 8-bit Gray)
    parameter LINE_LENGTH = 1024     // 이미지 가로 해상도 (예: VGA 640 등)
)(
    input  wire clk,
    input  wire reset,              // Active-high 리셋

    // 입력 인터페이스
    input  wire photo_data_valid,   // 입력 데이터 유효 신호
    input  wire [DATA_WIDTH-1:0] pixel_data_in,
    
    // 출력 인터페이스
    output reg  line_data_valid,    // 3개 라인이 모두 채워진 후 출력 유효 신호
    output reg  [DATA_WIDTH-1:0] line_out0, // 현재 라인 (Line 0)
    output reg  [DATA_WIDTH-1:0] line_out1, // 1라인 지연 (Line 1)
    output reg  [DATA_WIDTH-1:0] line_out2  // 2라인 지연 (Line 2)
);

    // [핵심 변경] Vivado 컴파일러에게 BRAM(Block RAM) 자원을 강제 사용하도록 지시
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] ram_0 [0:LINE_LENGTH-1];
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] ram_1 [0:LINE_LENGTH-1];
    
    reg [$clog2(LINE_LENGTH)-1:0] ptr;
    reg [2:0] line_cnt;
    
    // BRAM 출력을 임시로 받아줄 내부 와이어/레지스터 (Read-Before-Write 해결용)
    reg [DATA_WIDTH-1:0] ram_0_out;
    reg [DATA_WIDTH-1:0] ram_1_out;

    // BRAM 동시 읽기 로직 (현재 포인터 위치의 이전 저장 데이터 읽기)
    always @(posedge clk) begin
        if (photo_data_valid) begin
            ram_0_out <= ram_0[ptr];
            ram_1_out <= ram_1[ptr];
        end
    end

    // BRAM 쓰기 및 포인터/출력 제어 로직
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ptr             <= 0;
            line_cnt        <= 0;
            line_data_valid <= 1'b0;
            line_out0       <= 0;
            line_out1       <= 0;
            line_out2       <= 0;
        end 
        else if (photo_data_valid) begin
            // [1. 메모리 순차 업데이트] 
            // 현재 클럭에 읽어온 옛날 값을 다음 램으로 밀어 넣음 (BRAM 구조 매핑)
            ram_0[ptr] <= pixel_data_in; 
            ram_1[ptr] <= ram_0_out;  
            
            // [2. 3라인 출력 데이터 생성]
            line_out0  <= pixel_data_in;  
            line_out1  <= ram_0_out;     
            line_out2  <= ram_1_out;     
            
            // [3. 포인터 및 라인 카운터 제어]
            if (ptr == LINE_LENGTH - 1) begin
                ptr <= 0;
                if (line_cnt < 3'd3) begin
                    line_cnt <= line_cnt + 1;
                end
            end else begin
                ptr <= ptr + 1;
            end
            
            // [4. 출력 유효성 판단]
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
