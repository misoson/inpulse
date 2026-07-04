`timescale 1ns / 1ps
//=============================================================================
// File        : reset_bridge.v
// Description : Active-High(sync/async 혼용) reset -> Active-Low async reset
//               극성 변환 브릿지
//
// Design Notes:
//   - pe_ctrl 의 reset 은 posedge clk or posedge reset 감도리스트를 사용하므로
//     "비동기 assert, 이 always 블록 내에서 동기적으로 유지" 되는 표준 비동기
//     리셋 방식입니다. activation_unit 은 이를 Active-Low(reset_n)로 그대로
//     넘겨받기만 하면 되므로 단순 극성 반전(~reset)이 논리적으로는 충분합니다.
//   - 다만 두 모듈이 물리적으로 다른 위치/블록에 있을 가능성을 고려해,
//     리셋 해제(deassertion) 타이밍이 클럭 엣지에 깔끔히 정렬되도록
//     2-FF 동기화 방식의 "async assert / sync de-assert" 리셋 브릿지로
//     구성했습니다.
//   - Assert 시점은 즉시(비동기) 반영되므로 pe_ctrl 과 activation_unit 이
//     같은 사이클에 함께 리셋 상태로 들어갑니다. Deassert 만 1clk 늦게
//     풀리므로, 리셋 해제 후 첫 유효 데이터가 들어오기 전에 안전하게
//     reset_n 이 안정화됩니다(파이프라인 valid 흐름에는 영향 없음).
//=============================================================================
module reset_bridge (
    input  wire clk,
    input  wire reset,     // Active-High, pe_ctrl과 동일 클럭 도메인의 리셋
    output wire reset_n    // Active-Low, activation_unit 용
);

    reg sync0, sync1;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // 비동기 assert : reset 이 뜨는 즉시 두 FF 모두 0으로 클리어
            sync0 <= 1'b0;
            sync1 <= 1'b0;
        end else begin
            // 동기 de-assert : 2단 시프트 후에만 reset_n = 1 로 해제
            sync0 <= 1'b1;
            sync1 <= sync0;
        end
    end

    assign reset_n = sync1;

endmodule