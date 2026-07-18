`timescale 1ns / 1ps
//=====================================================================
// fsm_controller.v (수정본)
//
// Gated Convolution NPU - Central Control Unit
//   - Feature 트랙(pe_array 인스턴스 #0)과 Gate 트랙(pe_array 인스턴스 #1)을
//     동시에 제어하면서
//       1) 레이어별 mode_int4 매칭
//       2) 3-Line Buffer 리드 인에이블 및 PE in_valid 타이밍 제어
//       3) 두 트랙 간 출력 정합
//     을 담당한다.
//=====================================================================

module fsm_controller #(
    parameter DATA_WIDTH      = 8,   // pe.v / line_buffer.v의 line_out 데이터 폭
    parameter LBUF_RD_LATENCY = 1,   // 3-Line Buffer의 rd_en -> line_out 유효까지 지연 클럭 수
    parameter SYNC_FIFO_DEPTH = 4    // 하위 호환을 위해 파라미터는 유지 (내부에서는 더 이상 사용하지 않음)
)(
    input  wire clk,
    input  wire reset,                 // active-high, pe.v와 동일 방식

    //-----------------------------------------------------------
    // 상위 레이어 제어 인터페이스 (레이어 단위 제어)
    //-----------------------------------------------------------
    input  wire        layer_start,     // 1클럭 펄스: 새 레이어 처리 시작
    input  wire        layer_is_deep,   // 0: 초기 레이어(Feature=INT8) / 1: 깊은 레이어(Feature=INT4)
    input  wire [15:0] layer_out_pixels,// 이 레이어에서 생성되는 "유효 출력" 개수
    output reg         layer_done,      // 1클럭 펄스: 레이어 처리 완료

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
    // PE Array로 나가는 제어 신호 - Feature 트랙
    //-----------------------------------------------------------
    output reg                    feat_in_valid,
    output reg                    feat_mode_int4,
    output wire                   feat_pe_en,

    //-----------------------------------------------------------
    // PE Array로 나가는 제어 신호 - Gate 트랙
    //-----------------------------------------------------------
    output reg                    gate_in_valid,
    output reg                    gate_mode_int4,  // 항상 1 (Gate는 항상 INT4)
    output wire                   gate_pe_en,

    //-----------------------------------------------------------
    // PE Array로부터 받는 결과
    //-----------------------------------------------------------
    input  wire                   feat_valid_out,
    input  wire signed [31:0]     feat_conv_out,
    input  wire                   gate_valid_out,
    input  wire signed [31:0]     gate_conv_out,

    //-----------------------------------------------------------
    // 정합된 출력 (단순 pass-through, 하위 호환용 포트)
    //-----------------------------------------------------------
    output reg                    sync_valid_out,
    output reg  signed [31:0]     feat_conv_sync,
    output reg  signed [31:0]     gate_conv_sync
);

    //=================================================================
    // 0. 레이어 FSM 상태 정의
    //=================================================================
    localparam S_IDLE  = 2'd0;  // 대기
    localparam S_RUN   = 2'd1;  // 리드버퍼 리드 + PE 스트리밍
    localparam S_DRAIN = 2'd2;  // 마지막 픽셀 이후 파이프라인 flush 대기
    localparam S_DONE  = 2'd3;  // 완료 펄스 1클럭

    reg [1:0]  state, state_n;

    // 레이어 시작 시점의 모드를 래치
    reg        mode_int4_latched;

    reg [15:0] rd_cnt;        // 이번 레이어에서 지금까지 발생한 rd_en(=in_valid 요청) 수
    reg [15:0] out_cnt;       // 이번 레이어에서 지금까지 받은 sync_valid_out 수

    wire rd_done  = (rd_cnt  >= layer_out_pixels);
    wire out_done = (out_cnt >= layer_out_pixels);

    //=================================================================
    // 1. 상태 레지스터 (Sequential)
    //=================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) state <= S_IDLE;
        else       state <= state_n;
    end

    //=================================================================
    // 2. 다음 상태 결정 (Combinational)
    //=================================================================
    always @(*) begin
        state_n = state;
        case (state)
            S_IDLE:  if (layer_start) state_n = S_RUN;
            S_RUN:   if (rd_done)     state_n = S_DRAIN;
            S_DRAIN: if (out_done)    state_n = S_DONE;
            S_DONE:                   state_n = S_IDLE;
            default:                  state_n = S_IDLE;
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
            layer_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    rd_cnt  <= 16'd0;
                    out_cnt <= 16'd0;
                    if (layer_start)
                        mode_int4_latched <= layer_is_deep;
                end

                S_RUN: begin
                    if (feat_lbuf_rd_en)
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
    // 4. mode_int4 신호 분배
    //=================================================================
    always @(*) begin
        feat_mode_int4 = mode_int4_latched;
        gate_mode_int4 = 1'b1; // Gate 트랙은 항상 INT4
    end

    //=================================================================
    // 5. Line Buffer rd_en 생성
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
    // 6. rd_en -> in_valid 타이밍 보정 (LBUF_RD_LATENCY 반영)
    //=================================================================
    generate
        if (LBUF_RD_LATENCY <= 0) begin : g_no_delay
            always @(*) begin
                feat_in_valid = feat_lbuf_rd_en;
                gate_in_valid = gate_lbuf_rd_en;
            end
        end
        else if (LBUF_RD_LATENCY == 1) begin : g_delay_1
            reg feat_rd_dly;
            reg gate_rd_dly;

            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    feat_rd_dly <= 1'b0;
                    gate_rd_dly <= 1'b0;
                end
                else begin
                    feat_rd_dly <= feat_lbuf_rd_en;
                    gate_rd_dly <= gate_lbuf_rd_en;
                end
            end

            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    feat_in_valid <= 1'b0;
                    gate_in_valid <= 1'b0;
                end
                else begin
                    feat_in_valid <= feat_rd_dly;
                    gate_in_valid <= gate_rd_dly;
                end
            end
        end
        else begin : g_delay_n
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

    assign feat_pe_en = (state == S_RUN) || (state == S_DRAIN);
    assign gate_pe_en = feat_pe_en;

    //=================================================================
    // 7. 출력 정합 (단순 pass-through)
    //=================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sync_valid_out <= 1'b0;
            feat_conv_sync <= 32'sd0;
            gate_conv_sync <= 32'sd0;
        end
        else begin
            sync_valid_out <= feat_valid_out & gate_valid_out;

            if (feat_valid_out)
                feat_conv_sync <= feat_conv_out;
            if (gate_valid_out)
                gate_conv_sync <= gate_conv_out;
        end
    end

endmodule
