`timescale 1ns / 1ps

module pipeline_matcher #(
    parameter DATA_WIDTH = 32
)(
    input  wire        clk,
    input  wire        reset,      // Active-high
    input  wire        enable,
    
    // FSM 컨트롤러로부터 받는 제어 신호들
    input  wire        in_valid,
    input  wire        mode_int4,
    
    // 다음 스테이지(Activation 및 출력단)로 토스할 제어 신호들
    output reg         stage4_valid, // 최종 4클락 지연된 유효 신호
    output reg         out_mode_int4 // 타이밍에 맞춰 같이 내보낼 모드 신호
);

    // 4단계 딜레이 레지스터 체인
    reg [3:0] valid_delay_chain;
    reg [3:0] mode_delay_chain; // 모드 신호도 파이프라인 타이밍을 맞춰서 함께 이동

    // 순차 회로 블록: 클락 에지마다 신호를 한 칸씩 시프트
    always @(posedge clk) begin
        if (reset) begin
            valid_delay_chain <= 4'b0;
            mode_delay_chain  <= 4'b0;
        end
        else if (enable) begin
            // Valid 신호와 Mode 신호를 클락마다 한 칸씩 시프트(밀어주기)
            valid_delay_chain <= {valid_delay_chain[2:0], in_valid};
            mode_delay_chain  <= {mode_delay_chain[2:0], mode_int4};
        end
    end

    // 조합 회로 블록: 레지스터 체인의 맨 마지막(4번째) 값을 출력으로 직결
    always @(*) begin
        stage4_valid  = valid_delay_chain[3]; // 4클락 지연된 최상위 비트 출력
        out_mode_int4 = mode_delay_chain[3];  // 데이터와 타이밍이 맞춰진 모드 신호
    end

endmodule
