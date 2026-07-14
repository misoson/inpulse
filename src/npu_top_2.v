`timescale 1ns / 1ps
//=====================================================================
// npu_top.v
//
// Gated Convolution NPU - Top Level Wrapper
//
//   - Feature Track (PE #0) & Gate Track (PE #1) 병렬 배치
//   - 3-Line Buffer (Feature / Gate 각각 존재 가정)
//   - fsm_controller를 중앙 제어 장치로 통합하여 
//     리드 타이밍, 동작 정밀도, 출력 동기화(Rendezvous)를 제어함.
//=====================================================================

module npu_top #(
    parameter DATA_WIDTH      = 8,
    parameter LBUF_RD_LATENCY = 1,
    parameter SYNC_FIFO_DEPTH = 4
)(
    input  wire        clk,
    input  wire        reset,          // Active-High

    //-----------------------------------------------------------
    // 상위 시퀀서 (호스트) 인터페이스
    //-----------------------------------------------------------
    input  wire        layer_start,     // 레이어 시작 트리거 (1 clk pulse)
    input  wire        layer_is_deep,   // 0: INT8 (초기), 1: INT4 (심층)
    input  wire [15:0] layer_out_pixels,// 이번 레이어에서 처리할 총 출력 픽셀 수
    output wire        layer_done,      // 레이어 처리 완료 플래그 (1 clk pulse)

    //-----------------------------------------------------------
    // 외부 3-Line Buffer 데이터 입력 (Feature / Gate 각 트랙)
    //-----------------------------------------------------------
    // * 주의: fsm_controller에서 나가는 rd_en 신호가 이 라인 버퍼들의 리드 포트로 연결되어야 합니다.
    output wire        feat_lbuf_rd_en,
    input  wire [DATA_WIDTH-1:0] feat_line_out0,
    input  wire [DATA_WIDTH-1:0] feat_line_out1,
    input  wire [DATA_WIDTH-1:0] feat_line_out2,

    output wire        gate_lbuf_rd_en,
    input  wire [DATA_WIDTH-1:0] gate_line_out0,
    input  wire [DATA_WIDTH-1:0] gate_line_out1,
    input  wire [DATA_WIDTH-1:0] gate_line_out2,

    //-----------------------------------------------------------
    // NPU 최종 정합 출력 (Feature * Sigmoid(Gate) 연산 유닛 등으로 입력됨)
    //-----------------------------------------------------------
    output wire        npu_valid_out,
    output wire signed [31:0] npu_feat_conv_sync,
    output wire signed [31:0] npu_gate_conv_sync
);

    //=================================================================
    // 내부 제어 신호선 정의 (fsm_controller <-> PE / Buffers)
    //=================================================================
    // Feature Track 제어선
    wire        feat_in_valid;
    wire        feat_mode_int4;
    wire        feat_pe_en;
    wire        feat_raw_valid_out;
    wire signed [31:0] feat_raw_conv_out;

    // Gate Track 제어선
    wire        gate_in_valid;
    wire        gate_mode_int4;
    wire        gate_pe_en;
    wire        gate_raw_valid_out;
    wire signed [31:0] gate_raw_conv_out;


    //=================================================================
    // 1. Central FSM Controller 인스턴스화
    //=================================================================
    fsm_controller #(
        .DATA_WIDTH(DATA_WIDTH),
        .LBUF_RD_LATENCY(LBUF_RD_LATENCY),
        .SYNC_FIFO_DEPTH(SYNC_FIFO_DEPTH)
    ) u_fsm_controller (
        .clk                 (clk),
        .reset               (reset),

        // 상위 시퀀서 인터페이스
        .layer_start         (layer_start),
        .layer_is_deep       (layer_is_deep),
        .layer_out_pixels    (layer_out_pixels),
        .layer_done          (layer_done),

        // 3-Line Buffer 리드 인에이블 맵핑
        .feat_lbuf_rd_en     (feat_lbuf_rd_en),
        .feat_line_out0      (feat_line_out0),
        .feat_line_out1      (feat_line_out1),
        .feat_line_out2      (feat_line_out2),

        .gate_lbuf_rd_en     (gate_lbuf_rd_en),
        .gate_line_out0      (gate_line_out0),
        .gate_line_out1      (gate_line_out1),
        .gate_line_out2      (gate_line_out2),

        // PE Array 제어 신호 - Feature 트랙
        .feat_in_valid       (feat_in_valid),
        .feat_mode_int4      (feat_mode_int4),
        .feat_pe_en          (feat_pe_en),

        // PE Array 제어 신호 - Gate 트랙
        .gate_in_valid       (gate_in_valid),
        .gate_mode_int4      (gate_mode_int4),
        .gate_pe_en          (gate_pe_en),

        // PE로부터 피드백되는 원시 결과 수집
        .feat_valid_out      (feat_raw_valid_out),
        .feat_conv_out       (feat_raw_conv_out),
        .gate_valid_out      (gate_raw_valid_out),
        .gate_conv_out       (gate_raw_conv_out),

        // 내부 FIFO에 의해 시간축 정합 완료된 출력 신호
        .sync_valid_out      (npu_valid_out),
        .feat_conv_sync      (npu_feat_conv_sync),
        .gate_conv_sync      (npu_gate_conv_sync)
    );


    //=================================================================
    // 2. PE (Processing Element) #0 인스턴스화 - Feature Track
    //    (자체 윈도우 생성 기능이 포함된 pe.v 스펙 적용)
    //=================================================================
    pe #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_pe_feature (
        .clk                 (clk),
        .reset               (reset),
        
        // fsm_controller에서 제어되는 신호들과 1:1 결합
        .in_valid            (feat_in_valid),
        .mode_int4           (feat_mode_int4),
        
        // 3-Line Buffer로부터 바로 들어가는 라인 데이터
        .line_in0            (feat_line_out0),
        .line_in1            (feat_line_out1),
        .line_in2            (feat_line_out2),

        // 연산 결과 -> fsm_controller의 동기화 FIFO 입력으로 직결
        .valid_out           (feat_raw_valid_out),
        .conv_out            (feat_raw_conv_out)
    );


    //=================================================================
    // 3. PE (Processing Element) #1 인스턴스화 - Gate Track
    //    (항상 INT4 정밀도로 연산 수행하는 Gate 전용 트랙)
    //=================================================================
    pe #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_pe_gate (
        .clk                 (clk),
        .reset               (reset),
        
        // fsm_controller에서 제어되는 신호들과 1:1 결합
        .in_valid            (gate_in_valid),
        .mode_int4           (gate_mode_int4), // 컨트롤러가 항상 1'b1로 전달함
        
        // 3-Line Buffer로부터 바로 들어가는 라인 데이터
        .line_in0            (gate_line_out0),
        .line_in1            (gate_line_out1),
        .line_in2            (gate_line_out2),

        // 연산 결과 -> fsm_controller의 동기화 FIFO 입력으로 직결
        .valid_out           (gate_raw_valid_out),
        .conv_out            (gate_raw_conv_out)
    );

endmodule
