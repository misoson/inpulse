`timescale 1ns / 1ps

module pe_ctrl (
    // [1. 시스템 기본 신호]
    input wire clk,                // 100MHz 가상 클록 (주기 10ns)
    input wire rst_n,              // Active-Low 리셋 (0일 때 초기화)
    input wire mode_int4,
    
    // [2. 내부 모듈 인터페이스 (from pe_mac.v)]
    // TODO: MAC과 비트 폭([31:0]) 및 valid 의미 재확인
    input wire signed [31:0] mac_result, // MAC 연산부에서 bias까지 더해져 나온 결과값, 32비트
    input wire valid_d,                  // MAC에서 보내준 연산 완료 타이밍 신호
    
    // [3. 외부 모듈 인터페이스 (to Activation Unit)]
    output reg signed [31:0] conv_out,  // 파이프라인/출력 레지스터
    output reg valid_out                // Activation Unit을 깨우는 연산 완료 신호
);

    // -------------------------------------------------------------------------
    // Overflow & Saturation (포화) 처리 (조합회로)
    // -------------------------------------------------------------------------
    // 설명: mac_result가 한계치(임시: +/- 10000)를 넘을 때, 값이 뒤집히지 않도록
    //      최댓값/최솟값으로 고정 (Signed 연산 주의: sd 사용)
    
    wire signed [31:0] saturated_result;
    
    // 조건 연산자를 이용한 포화 처리 예시
    assign saturated_result = (mac_result > 32'sd2047) ? 32'sd2047 : // 상한선 돌파 시 고정
                              (mac_result < -32'sd2047) ? -32'sd2047 : // 하한선 돌파 시 고정
                              mac_result;                            // 정상 범위 내 값 패스
    //INT4 연산 스케일에 맞춰서 Saturation 임계값을 2047로 맞춤
    // -------------------------------------------------------------------------
    // Pipeline Register 래칭 & Valid 생성 (순차회로)
    // -------------------------------------------------------------------------
    // 설명: 클록 상승 에지(posedge clk)에서만 작동하며, 날것의 데이터를 레지스터에 안전하게 담아 깨끗한 출력 신호로 내보냄. 이 과정에서 1클록의 타이밍 지연(latency) 발생
    
    always @(posedge clk) begin
        if (!rst_n) begin
            // 리셋 상황 시 모든 출력 및 내부 레지스터를 0으로 초기화
            conv_out  <= 32'b0;
            valid_out <= 1'b0;
        end else begin
            // 파이프라인 레지스터를 거쳐 안정적인 신호 출력
            conv_out  <= saturated_result;
            // 입력 valid_d 신호를 1클록 지연시켜 valid_out으로 출력 (싱크 맞춤)
            valid_out <= valid_d;
        end
    end

endmodule
