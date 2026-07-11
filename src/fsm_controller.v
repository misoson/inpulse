`timescale 1ns / 1ps
//=====================================================================
// fsm_controller.v
//
// Gated Convolution NPU - Central Control Unit
//
//   - Feature 트랙(pe.v 인스턴스 #0)과 Gate 트랙(pe.v 인스턴스 #1)을
//     동시에 구동하면서
//       1) 레이어별 mode_int4 스위칭 (Feature: 초기=INT8/심층=INT4,
//          Gate: 항상 INT4)
//       2) 3-Line Buffer 리드 인에이블 및 pe.v in_valid 타이밍 정합
//       3) 두 트랙 간 2~3 클록 지연 비대칭을 흡수하는
//          Register Pipeline Matcher(핑퐁/소형 FIFO 구조)
//     를 수행한다.
//
//   포트 이름/비트폭은 첨부된 pe.v (DATA_WIDTH=8 기준) 및
//   pe_input.v 의 line_out0/1/2[7:0], in_valid, mode_int4,
//   conv_out[31:0](signed), valid_out 규격과 100% 일치시켰다.
//
//   ** 중요 (하단 "정합성 체크리스트" 참고) **
//   본 컨트롤러는 pe.v를 "자체 윈도우 생성 기능 포함" 모듈로 보고
//   line_out0/1/2 를 pe.v에 직접 연결하는 구조를 전제로 설계했다.
//   pe_input.v 를 pe.v 앞단에 추가로 연결하지 말 것 (아래 설명 참조).
//=====================================================================

module fsm_controller #(
    parameter DATA_WIDTH      = 8,   // pe.v / pe_input.v 의 line_out 폭과 동일
    parameter LBUF_RD_LATENCY = 1,   // 3-Line Buffer의 rd_en -> line_out 유효까지의 동기 리드 지연 (BRAM 가정)
    parameter SYNC_FIFO_DEPTH = 4    // Feature/Gate 결과 정합용 소형 FIFO 깊이 (2~3clk 비대칭 + 여유)
)(
    input  wire clk,
    input  wire reset,                 // active-high, pe.v와 동일 극성

    //-----------------------------------------------------------
    // 상위 시퀀서 인터페이스 (레이어 단위 제어)
    //-----------------------------------------------------------
    input  wire        layer_start,     // 1클록 펄스: 새 레이어 처리 시작
    input  wire        layer_is_deep,   // 0: 초기 레이어(Feature=INT8) / 1: 심층 레이어(Feature=INT4)
    input  wire [15:0] layer_out_pixels,// 이 레이어에서 기대되는 "유효 출력" 개수
                                         // (pe.v 파이프라인 채움 지연을 상위에서 이미 고려한 값이어야 함, 하단 주석 참고)
    output reg         layer_done,      // 1클록 펄스: 레이어 처리 완료

    //-----------------------------------------------------------
    // 3-Line Buffer 인터페이스 - Feature 트랙
    //-----------------------------------------------------------
    output reg                    feat_lbuf_rd_en,
    input  wire [DATA_WIDTH-1:0]  feat_line_out0,
    input  wire [DATA_WIDTH-1:0]  feat_line_out1,
    input  wire [DATA_WIDTH-1:0]  feat_line_out2,

    //-----------------------------------------------------------
    // 3-Line Buffer 인터페이스 - Gate 트랙
    //-----------------------------------------------------------
    output reg                    gate_lbuf_rd_en,
    input  wire [DATA_WIDTH-1:0]  gate_line_out0,
    input  wire [DATA_WIDTH-1:0]  gate_line_out1,
    input  wire [DATA_WIDTH-1:0]  gate_line_out2,

    //-----------------------------------------------------------
    // PE Array (pe.v 인스턴스) 로 나가는 제어 신호 - Feature 트랙
    //-----------------------------------------------------------
    output reg                    feat_in_valid,   // pe.v.in_valid
    output reg                    feat_mode_int4,  // pe.v.mode_int4
    output wire                   feat_pe_en,       // PE Array 클럭 게이팅/모니터용 인에이블

    //-----------------------------------------------------------
    // PE Array (pe.v 인스턴스) 로 나가는 제어 신호 - Gate 트랙
    //-----------------------------------------------------------
    output reg                    gate_in_valid,   // pe.v.in_valid
    output reg                    gate_mode_int4,  // pe.v.mode_int4 (항상 1)
    output wire                   gate_pe_en,

    //-----------------------------------------------------------
    // pe.v 로부터 되받는 결과 (두 인스턴스의 valid_out / conv_out)
    //-----------------------------------------------------------
    input  wire                   feat_valid_out,        // pe.v.valid_out (Feature)
    input  wire signed [31:0]     feat_conv_out,         // pe.v.conv_out  (Feature)
    input  wire                   gate_valid_out,        // pe.v.valid_out (Gate)
    input  wire signed [31:0]     gate_conv_out,         // pe.v.conv_out  (Gate)

    //-----------------------------------------------------------
    // 시간 정합된 출력 (다음 단, 예: Feature * sigmoid(Gate) 게이팅 유닛으로)
    //-----------------------------------------------------------
    output reg                    sync_valid_out,
    output reg  signed [31:0]     feat_conv_sync,
    output reg  signed [31:0]     gate_conv_sync
);

    //=================================================================
    // 0. 레이어 FSM 상태 정의
    //=================================================================
    localparam S_IDLE  = 2'd0;  // 대기
    localparam S_RUN   = 2'd1;  // 라인버퍼 리드 + PE 스트리밍
    localparam S_DRAIN = 2'd2;  // 마지막 픽셀 이후 파이프라인 flush 대기
    localparam S_DONE  = 2'd3;  // 완료 펄스 1클록

    reg [1:0]  state, state_n;

    // 레이어 동안 유지되어야 하는 설정값 (mode_int4는 윈도우 캡처 도중
    // 절대 바뀌면 안 되므로 layer_start 시점에 래치해서 레이어 내내 고정)
    reg        mode_int4_latched;

    reg [15:0] rd_cnt;        // 이번 레이어에서 지금까지 발행한 rd_en(=in_valid 요청) 개수
    reg [15:0] out_cnt;       // 이번 레이어에서 지금까지 나온 sync_valid_out 개수

    wire rd_done  = (rd_cnt  >= layer_out_pixels);
    wire out_done = (out_cnt >= layer_out_pixels);

    //=================================================================
    // 1. 상태 전이 (Sequential)
    //=================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) state <= S_IDLE;
        else       state <= state_n;
    end

    //=================================================================
    // 2. 다음 상태 로직 (Combinational)
    //
    //   S_IDLE  --(layer_start)-->  S_RUN
    //   S_RUN   --(rd_done)     -->  S_DRAIN   : 더 이상 새 픽셀은 안 읽지만
    //                                            이미 밀어넣은 데이터가
    //                                            파이프라인을 빠져나올 때까지 대기
    //   S_DRAIN --(out_done)    -->  S_DONE    : 기대한 유효 출력 개수를
    //                                            모두 받으면 완료
    //   S_DONE  --(항상)         -->  S_IDLE
    //=================================================================
    always @(*) begin
        state_n = state;
        case (state)
            S_IDLE:  if (layer_start) state_n = S_RUN;
            S_RUN:   if (rd_done)     state_n = S_DRAIN;
            S_DRAIN: if (out_done)    state_n = S_DONE;
            S_DONE:                  state_n = S_IDLE;
            default:                 state_n = S_IDLE;
        endcase
    end

    //=================================================================
    // 3. 레이어 설정 래치 + 카운터
    //=================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mode_int4_latched <= 1'b0;
            rd_cnt            <= 16'd0;
            out_cnt           <= 16'd0;
            layer_done        <= 1'b0;
        end
        else begin
            layer_done <= 1'b0; // 기본값: 1클록 pulse

            case (state)
                S_IDLE: begin
                    rd_cnt  <= 16'd0;
                    out_cnt <= 16'd0;
                    if (layer_start)
                        // 초기 레이어=INT8(0), 심층 레이어=INT4(1)
                        // 이 값은 레이어가 끝날 때까지 절대 바뀌지 않는다.
                        // (pe.v는 in_valid 구간 도중 mode_int4가 바뀌면
                        //  3x3 window 안에서 INT8/INT4 데이터가 섞여
                        //  들어가는 치명적 오류가 발생한다.)
                        mode_int4_latched <= layer_is_deep;
                end

                S_RUN: begin
                    if (feat_lbuf_rd_en) // rd_en과 동일한 카운트 기준(Feature/Gate 동시 진행 가정)
                        rd_cnt <= rd_cnt + 16'd1;
                    if (sync_valid_out)
                        out_cnt <= out_cnt + 16'd1;
                end

                S_DRAIN: begin
                    if (sync_valid_out)
                        out_cnt <= out_cnt + 16'd1;
                end

                S_DONE: begin
                    layer_done <= 1'b1;
                end
            endcase
        end
    end

    //=================================================================
    // 4. mode_int4 신호 생성
    //    - Feature 트랙 : 레이어에 따라 INT8/INT4 스위칭
    //    - Gate 트랙    : 항상 INT4 고정
    //=================================================================
    always @(*) begin
        feat_mode_int4 = mode_int4_latched;
        gate_mode_int4 = 1'b1;
    end

    //=================================================================
    // 5. 3-Line Buffer 리드 인에이블
    //    Feature/Gate 트랙은 같은 픽셀 좌표를 병렬로 읽는다고 가정.
    //    (독립적으로 다른 시점에 stall 되는 구조라면 각 트랙별로
    //     별도 rd_cnt/FSM이 필요 - 정합성 체크리스트 참고)
    //=================================================================
    wire run_active = (state == S_RUN) && !rd_done;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            feat_lbuf_rd_en <= 1'b0;
            gate_lbuf_rd_en <= 1'b0;
        end
        else begin
            feat_lbuf_rd_en <= run_active;
            gate_lbuf_rd_en <= run_active;
        end
    end

    //=================================================================
    // 6. rd_en -> in_valid 타이밍 보정 (라인버퍼 리드 레이턴시 매칭)
    //
    //    [고려하지 못했을 가능성이 높은 타이밍 이슈]
    //    3-Line Buffer가 동기식(BRAM 등)이라면, rd_en을 올린 클록에는
    //    아직 line_out0/1/2에 "이전" 데이터가 남아있고, 실제 요청한
    //    데이터는 다음 클록에 나타난다 (LBUF_RD_LATENCY = 1 가정).
    //    만약 rd_en을 in_valid로 그대로 사용해 pe.v에 넣으면,
    //    pe.v는 한 클록 앞선(stale) line_out 값을 3x3 윈도우에
    //    캡처하게 되어 전체 컨볼루션 결과가 한 픽셀씩 밀리는
    //    오류가 발생한다. 이를 막기 위해 in_valid를 rd_en 대비
    //    LBUF_RD_LATENCY 만큼 지연시켜 line_out 데이터와 정확히
    //    동일 사이클에 pe.v로 진입하도록 정렬한다.
    //=================================================================
    generate
        if (LBUF_RD_LATENCY <= 0) begin : g_no_delay
            always @(*) begin
                feat_in_valid = feat_lbuf_rd_en;
                gate_in_valid = gate_lbuf_rd_en;
            end
        end
        else begin : g_delay
            reg [LBUF_RD_LATENCY-1:0] feat_rd_dly;
            reg [LBUF_RD_LATENCY-1:0] gate_rd_dly;

            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    feat_rd_dly <= {LBUF_RD_LATENCY{1'b0}};
                    gate_rd_dly <= {LBUF_RD_LATENCY{1'b0}};
                end
                else begin
                    feat_rd_dly <= {feat_rd_dly[LBUF_RD_LATENCY-2:0], feat_lbuf_rd_en};
                    gate_rd_dly <= {gate_rd_dly[LBUF_RD_LATENCY-2:0], gate_lbuf_rd_en};
                end
            end

            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    feat_in_valid <= 1'b0;
                    gate_in_valid <= 1'b0;
                end
                else begin
                    feat_in_valid <= feat_rd_dly[LBUF_RD_LATENCY-1];
                    gate_in_valid <= gate_rd_dly[LBUF_RD_LATENCY-1];
                end
            end
        end
    endgenerate

    // PE Array 인에이블(클록게이팅/모니터용) : RUN 또는 DRAIN 구간 내내 동작해야
    // 파이프라인에 이미 들어간 데이터가 끝까지 흘러나올 수 있다.
    assign feat_pe_en = (state == S_RUN) || (state == S_DRAIN);
    assign gate_pe_en = feat_pe_en;

    //=================================================================
    // 7. Register Pipeline Matcher (Feature/Gate 결과 시간 정합)
    //
    //    Feature 트랙과 Gate 트랙은 동일 좌표를 처리하지만 물리적으로
    //    분리된 pe.v 인스턴스이므로 2~3클록의 상대 지연이 생길 수
    //    있다고 명시하셨다. 어느 트랙이 더 빠를지 고정되어 있지 않을
    //    수 있으므로, 단순 고정 지연(shift register)이 아니라
    //    "먼저 도착한 트랙의 결과를 소형 FIFO에 보관했다가, 나중 트랙이
    //    도착하는 시점에 두 값을 동시에 방출"하는 정합(Rendezvous) 방식의
    //    핑퐁 버퍼로 구현했다. (엄밀한 2-entry 핑퐁으로는 3클록 스큐를
    //    다 흡수하지 못하므로, 여유를 둔 SYNC_FIFO_DEPTH=4 의 소형
    //    레지스터 FIFO로 일반화했다.)
    //=================================================================
    localparam PTR_W = $clog2(SYNC_FIFO_DEPTH);

    reg signed [31:0] feat_fifo [0:SYNC_FIFO_DEPTH-1];
    reg signed [31:0] gate_fifo [0:SYNC_FIFO_DEPTH-1];

    reg [PTR_W-1:0] feat_wr_ptr, feat_rd_ptr;
    reg [PTR_W-1:0] gate_wr_ptr, gate_rd_ptr;
    reg [PTR_W:0]   feat_cnt,    gate_cnt;   // 점유 개수 (오버플로우 확인용, depth+1 비트)

    integer i;

    // 두 FIFO가 모두 비어있지 않을 때만 "동시 방출"
    wire join_fire = (feat_cnt != 0) && (gate_cnt != 0);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            feat_wr_ptr <= {PTR_W{1'b0}};
            feat_rd_ptr <= {PTR_W{1'b0}};
            gate_wr_ptr <= {PTR_W{1'b0}};
            gate_rd_ptr <= {PTR_W{1'b0}};
            feat_cnt    <= {(PTR_W+1){1'b0}};
            gate_cnt    <= {(PTR_W+1){1'b0}};

            sync_valid_out <= 1'b0;
            feat_conv_sync <= 32'sd0;
            gate_conv_sync <= 32'sd0;

            for (i = 0; i < SYNC_FIFO_DEPTH; i = i + 1) begin
                feat_fifo[i] <= 32'sd0;
                gate_fifo[i] <= 32'sd0;
            end
        end
        else begin
            // --- Feature 결과 push ---
            if (feat_valid_out) begin
                feat_fifo[feat_wr_ptr] <= feat_conv_out;
                feat_wr_ptr            <= feat_wr_ptr + 1'b1;
            end

            // --- Gate 결과 push ---
            if (gate_valid_out) begin
                gate_fifo[gate_wr_ptr] <= gate_conv_out;
                gate_wr_ptr            <= gate_wr_ptr + 1'b1;
            end

            // --- 두 FIFO 모두 데이터가 있으면 동시 pop (정합 완료) ---
            if (join_fire) begin
                feat_conv_sync <= feat_fifo[feat_rd_ptr];
                gate_conv_sync <= gate_fifo[gate_rd_ptr];
                feat_rd_ptr    <= feat_rd_ptr + 1'b1;
                gate_rd_ptr    <= gate_rd_ptr + 1'b1;
                sync_valid_out <= 1'b1;
            end
            else begin
                sync_valid_out <= 1'b0;
            end

            // --- 점유 카운트 갱신 (push/pop 동시 발생 케이스 포함) ---
            case ({feat_valid_out, join_fire})
                2'b10:   feat_cnt <= feat_cnt + 1'b1;
                2'b01:   feat_cnt <= feat_cnt - 1'b1;
                2'b11:   feat_cnt <= feat_cnt;         // push와 pop 동시 -> 변화 없음
                default: feat_cnt <= feat_cnt;
            endcase

            case ({gate_valid_out, join_fire})
                2'b10:   gate_cnt <= gate_cnt + 1'b1;
                2'b01:   gate_cnt <= gate_cnt - 1'b1;
                2'b11:   gate_cnt <= gate_cnt;
                default: gate_cnt <= gate_cnt;
            endcase
        end
    end

endmodule