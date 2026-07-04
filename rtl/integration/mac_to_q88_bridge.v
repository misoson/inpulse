`timescale 1ns / 1ps
//=============================================================================
// File        : mac_to_q88_bridge.v
// Description : pe_ctrl 의 32bit 정수 saturation 결과(conv_out)를
//               activation_unit 이 요구하는 16bit Q8.8 고정소수점 포맷으로
//               변환하는 조합회로 브릿지
//
// Design Notes (비트 슬라이스/스케일링 근거):
//   pe_ctrl 은 mode_int4 에 따라 아래의 정수 상한/하한으로 saturation 함:
//       INT4 : +-2047    (2^11-1, 부호 포함 12bit 필요)
//       INT8 : +-524287  (2^19-1, 부호 포함 20bit 필요)
//
//   activation_unit 이 기대하는 Q8.8 은 16bit 전체 중 8bit 정수부(부호 포함)
//   + 8bit 소수부이며, 표현 가능한 최대값은 +32767(=+127.996), 최소값은
//   -32768(=-128.0) 입니다.
//
//   두 모드의 saturation 경계값이 서로 자릿수가 크게 다르므로, 단순히
//   32bit 중 [15:0] 을 그대로 잘라내면(단순 truncation)
//     - INT4 모드: 유효 비트가 12bit뿐이라 Q8.8 의 소수부 해상도를 거의
//       못 씀 (다이나믹 레인지 낭비)
//     - INT8 모드: 상위 유효 비트가 그대로 잘려나가 값이 깨짐(overflow)
//   두 문제가 동시에 발생합니다.
//
//   따라서 saturation 경계값이 Q8.8 의 최대 표현값(32767)에 최대한
//   근접하도록 "모드별 정렬 시프트(SHIFT_AMT=4)"를 적용합니다.
//
//     INT4 :  2047 <<< 4  = 32752  (~ +127.97 in Q8.8) -> 좌측 시프트
//             (작은 다이나믹 레인지를 16bit 폭에 맞춰 확장 -> 소수부 해상도 확보)
//     INT8 : 524287 >>> 4 = 32767  (~ +127.996 in Q8.8) -> 우측 시프트
//             (20bit 다이나믹 레인지를 16bit 로 압축 -> 상위 유효비트 보존)
//
//   즉, 시프트 이후에는 항상 |value| <= 32767 이 보장되므로, 상위
//   [31:16] 비트는 부호확장 비트만 남게 되고 이를 버리는 [15:0] 슬라이스는
//   "정보 손실이 없는(lossless) 슬라이스"가 됩니다.
//
//   주의(설계 가정): 이 스케일은 MAC 누산기의 이진소수점이 LSB에
//   위치한(순수 정수 누산) 것을 가정한 것입니다. 실제 가중치/활성화
//   양자화 스케일(예: weight 가 Qm.n 포맷인 경우)이 다르면 SHIFT_AMT 및
//   모드별 시프트 방향은 반드시 재검증/재계산되어야 합니다.
//
//   방어적 saturation: pe_ctrl 단계에서 이미 |conv_out| <= target_max 가
//   보장되고 SHIFT_AMT 도 이를 감안해 선택했지만, 향후 target_max/min
//   값이 변경되고 SHIFT_AMT 가 함께 갱신되지 않는 실수(설계 변경 누락)에
//   대비해 2차 saturation을 한번 더 넣어 16bit 슬라이스 시 부호反전
//   (wraparound) 사고를 원천 차단합니다.
//=============================================================================
module mac_to_q88_bridge #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_WIDTH = 8
)(
    input  wire signed [31:0]            conv_out,   // pe_ctrl 의 saturated 32bit 정수 결과
    input  wire                          mode_int4,  // 1: INT4 모드 / 0: INT8 모드
    output wire signed [DATA_WIDTH-1:0]  data_q88    // activation_unit 입력용 Q8.8
);

    localparam integer SHIFT_AMT = 4;

    // 모드별 정렬 시프트 (조합회로, 산술 시프트로 부호 보존)
    wire signed [31:0] shifted_val;
    assign shifted_val = mode_int4 ? (conv_out <<< SHIFT_AMT)   // INT4 : 좌측 시프트(scale up)
                                    : (conv_out >>> SHIFT_AMT); // INT8 : 우측 시프트(scale down)

    // 방어적 2차 saturation (Q8.8 16bit 부호 범위로 clip)
    localparam signed [31:0] Q88_MAX = 32'sd32767;   // 16bit signed max
    localparam signed [31:0] Q88_MIN = -32'sd32768;  // 16bit signed min

    wire signed [31:0] clipped_val;
    assign clipped_val = (shifted_val > Q88_MAX) ? Q88_MAX :
                          (shifted_val < Q88_MIN) ? Q88_MIN :
                          shifted_val;

    // 최종 슬라이스 : 위에서 이미 16bit 부호범위로 clip 했으므로
    // 상위 [31:16] 은 부호확장 비트 뿐 -> 하위 16bit 슬라이스는 무손실.
    assign data_q88 = clipped_val[DATA_WIDTH-1:0];

endmodule