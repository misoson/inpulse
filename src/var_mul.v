`timescale 1ns / 1ps

module var_mul (
    input wire mode_flag,       // 0: INT8 모드, 1: INT4 모드
    input wire [7:0] a,         // 입력 픽셀 (8-bit)
    input wire [7:0] b,         // 입력 가중치 (8-bit)
    output reg [15:0] p         // 곱셈 결과 출력 (16-bit)
);

    always @(*) begin
        if (mode_flag == 1'b0) begin
            // [INT8 모드] 8-bit * 8-bit 정밀 연산
            p = a * b;
        end else begin
            // [INT4 모드] 하드웨어 재사용 및 연산 분할 (Sub-word Parallelism)
            // 상위 4비트 끼리 곱한 결과(8비트)를 p의 상위 8비트에 배치
            p[15:8] = a[7:4] * b[7:4];
            // 하위 4비트 끼리 곱한 결과(8비트)를 p의 하위 8비트에 배치 (올림수 차단 완료)
            p[7:0]  = a[3:0] * b[3:0];
        end
    end

endmodule