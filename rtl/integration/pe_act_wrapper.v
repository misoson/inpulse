`timescale 1ns / 1ps
//=============================================================================
// File        : pe_act_wrapper.v
// Description : pe_ctrl (Active-High reset, 32bit 정수 saturation)
//               -> activation_unit (Active-Low reset, 16bit Q8.8) 를
//               연결하는 최상위 래퍼
//
// 해결한 인터페이스 충돌:
//   1) 리셋 극성/방식 : reset_bridge 로 Active-High -> Active-Low(async) 변환
//   2) 비트 폭        : mac_to_q88_bridge 로 32bit -> 16bit 변환
//   3) 데이터 포맷     : 위 브릿지에서 모드별 정렬 시프트로 정수->Q8.8 변환
//   4) 제어 신호       : pe_ctrl 에 없던 enable / track_sel 을 wrapper 상위
//                        포트로 새로 노출하여 activation_unit 에 직접 연결
//
// Latency / Valid 동기화:
//   pe_ctrl        : mac_result/valid_d  -> conv_out/valid_out   : 1 clk (레지스터)
//   bit-width bridge : conv_out          -> data_q88             : 0 clk (조합)
//   activation_unit  : data_in/valid_in  -> data_out/valid_out   : 1 clk (레지스터)
//   ---------------------------------------------------------------
//   Total : mac_result 인가 시점 기준 data_out 까지 정확히 2 clk latency.
//
//   pe_ctrl 의 valid_out(=pe_valid_out) 을 브릿지를 거치지 않고 그대로
//   activation_unit 의 valid_in 에 조합적으로 연결했기 때문에, 데이터와
//   valid 가 항상 같은 사이클에 함께 이동합니다. 즉 별도의 valid 지연
//   보정 로직 없이도 두 파이프라인 스테이지가 정확히 1:1로 정렬됩니다.
//   (만약 추후 브릿지에 타이밍 클로징을 위한 레지스터 스테이지를 추가한다면,
//    반드시 pe_valid_out 도 동일하게 1clk 딜레이시켜 activation_unit 에
//    넣어줘야 valid-data 정렬이 깨지지 않습니다.)
//
// enable(pe_enable) 연결에 대한 저전력 설계 참고:
//   온디바이스 초저전력 NPU 특성상, activation_unit 의 enable 은 단순히
//   1'b1 로 고정하기보다 상위 시퀀서의 global enable 과 AND 해서 넣거나,
//   추후 클럭/데이터 게이팅과 결합해 valid 가 없는 구간에는 내부 토글을
//   줄이는 방향으로 확장하는 것을 권장합니다. 본 wrapper 는 이를 위해
//   pe_enable 을 상위에서 자유롭게 제어할 수 있도록 포트로 노출만
//   해두었습니다.
//=============================================================================
module pe_act_wrapper #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_WIDTH = 8
)(
    // ---- 시스템 공통 ----
    input  wire                          clk,
    input  wire                          reset,      // Active-High (pe_ctrl 도메인 원본 리셋)
    input  wire                          mode_int4,  // 1: INT4 / 0: INT8

    // ---- pe_mac.v 로부터의 입력 (pe_ctrl 로 전달) ----
    input  wire signed [31:0]            mac_result,
    input  wire                          valid_d,

    // ---- activation_unit 제어용 신규 상위 포트 (기존에 누락되어 있던 신호) ----
    input  wire                          pe_enable,  // activation_unit enable
    input  wire                          track_sel,  // 0: ReLU(Feature) / 1: Sigmoid(Gate)

    // ---- 최종 출력 ----
    output wire signed [DATA_WIDTH-1:0]  data_out,
    output wire                          valid_out
);

    // 내부 연결 wire
    wire signed [31:0]           conv_out;
    wire                          pe_valid_out;
    wire                          reset_n;
    wire signed [DATA_WIDTH-1:0] bridged_data;

    //-------------------------------------------------------------------
    // 1) 리셋 브릿지
    //-------------------------------------------------------------------
    reset_bridge u_reset_bridge (
        .clk     (clk),
        .reset   (reset),
        .reset_n (reset_n)
    );

    //-------------------------------------------------------------------
    // 2) pe_ctrl 인스턴스 (원본 그대로, 수정 없음)
    //-------------------------------------------------------------------
    pe_ctrl u_pe_ctrl (
        .clk        (clk),
        .reset      (reset),
        .mode_int4  (mode_int4),
        .mac_result (mac_result),
        .valid_d    (valid_d),
        .conv_out   (conv_out),
        .valid_out  (pe_valid_out)
    );

    //-------------------------------------------------------------------
    // 3) 비트 폭 / 데이터 포맷 브릿지 (32bit 정수 -> 16bit Q8.8)
    //-------------------------------------------------------------------
    mac_to_q88_bridge #(
        .DATA_WIDTH (DATA_WIDTH),
        .FRAC_WIDTH (FRAC_WIDTH)
    ) u_mac_to_q88_bridge (
        .conv_out  (conv_out),
        .mode_int4 (mode_int4),
        .data_q88  (bridged_data)
    );

    //-------------------------------------------------------------------
    // 4) activation_unit 인스턴스 (원본 그대로, 수정 없음)
    //    - enable / track_sel 은 wrapper 신규 포트에서 직접 공급
    //    - valid_in 은 pe_valid_out 을 조합적으로 그대로 전달 (latency 정렬)
    //-------------------------------------------------------------------
    activation_unit #(
        .DATA_WIDTH (DATA_WIDTH),
        .FRAC_WIDTH (FRAC_WIDTH)
    ) u_activation_unit (
        .clk       (clk),
        .reset_n   (reset_n),
        .enable    (pe_enable),
        .track_sel (track_sel),
        .data_in   (bridged_data),
        .valid_in  (pe_valid_out),
        .data_out  (data_out),
        .valid_out (valid_out)
    );

endmodule