`timescale 1ns / 1ps

//=============================================================================
// File        : npu_top.v (수정본)
// Description : Optimized top module for Gated Convolution NPU
//
// 변경 사항 (원본 대비):
//   - 원본은 top-level 포트 총합이 169비트였는데, XC7Z020CLG400의 유저 I/O
//     한도는 125개뿐이라 Bonded IOB 초과(169 > 125)가 발생했습니다.
//   - [1] feat_weight_wr_*(37bit) / gate_weight_wr_*(37bit) 두 세트를
//         weight_wr_target 1bit로 선택하는 공용 버스 하나로 통합
//         (74bit -> 38bit)
//   - [2] out_ch0~3[15:0](64bit) + output_valid(1bit)를 4-cycle 시분할
//         출력(out_data[15:0] + out_ch_sel[1:0] + output_valid)으로 변경
//         (65bit -> 19bit)
//   - 합계 169bit -> 87bit로 축소, 125핀 한도 내로 확보
//   - line_buffer / weight_buffer / pe_array / fsm_controller / activation_unit
//     인스턴스 연결 로직 자체는 원본과 동일 (내부 아키텍처는 변경하지 않음)
//=============================================================================

module npu_top #(
    parameter DATA_WIDTH        = 8,
    parameter LINE_LENGTH       = 1024,
    parameter ACT_DATA_WIDTH    = 16,
    parameter FRAC_WIDTH        = 8,
    parameter CONV_TO_ACT_SHIFT = 0,
    parameter LBUF_RD_LATENCY   = 1,
    parameter SYNC_FIFO_DEPTH   = 4
)(
    input  wire clk,
    input  wire reset,

    // Layer control
    input  wire        layer_start,
    input  wire        layer_is_deep,
    input  wire [15:0] layer_out_pixels,
    output wire        layer_done,

    // Input pixel stream
    input  wire                  photo_data_valid,
    input  wire [DATA_WIDTH-1:0] pixel_data_in,

    // [수정] Feature/Gate weight_buffer 쓰기 포트를 공용 버스로 통합
    //   weight_wr_target : 0 = Feature weight_buffer로 씀, 1 = Gate weight_buffer로 씀
    input  wire        weight_wr_en,
    input  wire        weight_wr_target,
    input  wire [3:0]  weight_wr_addr,
    input  wire [31:0] weight_wr_data,

    // [수정] 4채널 출력(out_ch0~3)을 4-cycle에 걸쳐 시분할 전송
    //   out_ch_sel이 몇 번째 채널인지 알려주고, 그 사이클에 out_data가 유효
    output reg  signed [ACT_DATA_WIDTH-1:0] out_data,
    output reg  [1:0]                       out_ch_sel,
    output reg                              output_valid
);

    //=========================================================================
    // 1. Reset conversion
    //=========================================================================

    wire reset_n;
    assign reset_n = ~reset;

    //=========================================================================
    // 2. FSM control signals
    //=========================================================================

    wire feat_lbuf_rd_en;
    wire gate_lbuf_rd_en;

    wire feat_in_valid_ctrl;
    wire gate_in_valid_ctrl;

    wire feat_mode_int4;
    wire gate_mode_int4;

    wire feat_pe_en;
    wire gate_pe_en;

    wire               fsm_sync_valid;
    wire signed [31:0] fsm_feat_conv_sync;
    wire signed [31:0] fsm_gate_conv_sync;

    //======================================================================
    // Feature Weight Buffer Wires
    //======================================================================

    wire signed [DATA_WIDTH-1:0] feat_pe0_weight_0, feat_pe0_weight_1, feat_pe0_weight_2, feat_pe0_weight_3;
    wire signed [DATA_WIDTH-1:0] feat_pe0_weight_4, feat_pe0_weight_5, feat_pe0_weight_6, feat_pe0_weight_7;
    wire signed [DATA_WIDTH-1:0] feat_pe0_weight_8;

    wire signed [DATA_WIDTH-1:0] feat_pe1_weight_0, feat_pe1_weight_1, feat_pe1_weight_2, feat_pe1_weight_3;
    wire signed [DATA_WIDTH-1:0] feat_pe1_weight_4, feat_pe1_weight_5, feat_pe1_weight_6, feat_pe1_weight_7;
    wire signed [DATA_WIDTH-1:0] feat_pe1_weight_8;

    wire signed [DATA_WIDTH-1:0] feat_pe2_weight_0, feat_pe2_weight_1, feat_pe2_weight_2, feat_pe2_weight_3;
    wire signed [DATA_WIDTH-1:0] feat_pe2_weight_4, feat_pe2_weight_5, feat_pe2_weight_6, feat_pe2_weight_7;
    wire signed [DATA_WIDTH-1:0] feat_pe2_weight_8;

    wire signed [DATA_WIDTH-1:0] feat_pe3_weight_0, feat_pe3_weight_1, feat_pe3_weight_2, feat_pe3_weight_3;
    wire signed [DATA_WIDTH-1:0] feat_pe3_weight_4, feat_pe3_weight_5, feat_pe3_weight_6, feat_pe3_weight_7;
    wire signed [DATA_WIDTH-1:0] feat_pe3_weight_8;

    wire signed [31:0] feat_pe0_bias;
    wire signed [31:0] feat_pe1_bias;
    wire signed [31:0] feat_pe2_bias;
    wire signed [31:0] feat_pe3_bias;

    //======================================================================
    // Gate Weight Buffer Wires
    //======================================================================

    wire signed [DATA_WIDTH-1:0] gate_pe0_weight_0, gate_pe0_weight_1, gate_pe0_weight_2, gate_pe0_weight_3;
    wire signed [DATA_WIDTH-1:0] gate_pe0_weight_4, gate_pe0_weight_5, gate_pe0_weight_6, gate_pe0_weight_7;
    wire signed [DATA_WIDTH-1:0] gate_pe0_weight_8;

    wire signed [DATA_WIDTH-1:0] gate_pe1_weight_0, gate_pe1_weight_1, gate_pe1_weight_2, gate_pe1_weight_3;
    wire signed [DATA_WIDTH-1:0] gate_pe1_weight_4, gate_pe1_weight_5, gate_pe1_weight_6, gate_pe1_weight_7;
    wire signed [DATA_WIDTH-1:0] gate_pe1_weight_8;

    wire signed [DATA_WIDTH-1:0] gate_pe2_weight_0, gate_pe2_weight_1, gate_pe2_weight_2, gate_pe2_weight_3;
    wire signed [DATA_WIDTH-1:0] gate_pe2_weight_4, gate_pe2_weight_5, gate_pe2_weight_6, gate_pe2_weight_7;
    wire signed [DATA_WIDTH-1:0] gate_pe2_weight_8;

    wire signed [DATA_WIDTH-1:0] gate_pe3_weight_0, gate_pe3_weight_1, gate_pe3_weight_2, gate_pe3_weight_3;
    wire signed [DATA_WIDTH-1:0] gate_pe3_weight_4, gate_pe3_weight_5, gate_pe3_weight_6, gate_pe3_weight_7;
    wire signed [DATA_WIDTH-1:0] gate_pe3_weight_8;

    wire signed [31:0] gate_pe0_bias;
    wire signed [31:0] gate_pe1_bias;
    wire signed [31:0] gate_pe2_bias;
    wire signed [31:0] gate_pe3_bias;

    //=========================================================================
    // 3. [수정] Weight 쓰기 버스 디먹스
    //
    //    weight_wr_target으로 feat/gate weight_buffer 중 하나만 wr_en이
    //    걸리도록 분기. 주소/데이터 버스는 공유.
    //=========================================================================

    wire feat_weight_wr_en_i;
    wire gate_weight_wr_en_i;

    assign feat_weight_wr_en_i = weight_wr_en & ~weight_wr_target;
    assign gate_weight_wr_en_i = weight_wr_en &  weight_wr_target;

    //=========================================================================
    // 4. Shared Line Buffer
    //=========================================================================

    wire lbuf_stream_enable;
    assign lbuf_stream_enable = photo_data_valid && (feat_lbuf_rd_en || gate_lbuf_rd_en);

    wire                  line_data_valid;
    wire [DATA_WIDTH-1:0] line_out0;
    wire [DATA_WIDTH-1:0] line_out1;
    wire [DATA_WIDTH-1:0] line_out2;

    line_buffer #(
        .DATA_WIDTH  (DATA_WIDTH),
        .LINE_LENGTH (LINE_LENGTH)
    ) u_line_buffer (
        .clk              (clk),
        .reset            (reset),

        .photo_data_valid (lbuf_stream_enable),
        .pixel_data_in    (pixel_data_in),

        .line_data_valid  (line_data_valid),
        .line_out0        (line_out0),
        .line_out1        (line_out1),
        .line_out2        (line_out2)
    );

    wire feat_array_in_valid;
    wire gate_array_in_valid;

    assign feat_array_in_valid = feat_in_valid_ctrl;
    assign gate_array_in_valid = gate_in_valid_ctrl;

    //=========================================================================
    // 5. Weight Buffers (Feature & Gate)
    //=========================================================================

    weight_buffer #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_feat_weight_buffer (
        .clk(clk),
        .reset(reset),

        .wr_en(feat_weight_wr_en_i),
        .wr_addr(weight_wr_addr),
        .wr_data(weight_wr_data),

        .pe0_weight_0(feat_pe0_weight_0), .pe0_weight_1(feat_pe0_weight_1),
        .pe0_weight_2(feat_pe0_weight_2), .pe0_weight_3(feat_pe0_weight_3),
        .pe0_weight_4(feat_pe0_weight_4), .pe0_weight_5(feat_pe0_weight_5),
        .pe0_weight_6(feat_pe0_weight_6), .pe0_weight_7(feat_pe0_weight_7),
        .pe0_weight_8(feat_pe0_weight_8), .pe0_bias(feat_pe0_bias),

        .pe1_weight_0(feat_pe1_weight_0), .pe1_weight_1(feat_pe1_weight_1),
        .pe1_weight_2(feat_pe1_weight_2), .pe1_weight_3(feat_pe1_weight_3),
        .pe1_weight_4(feat_pe1_weight_4), .pe1_weight_5(feat_pe1_weight_5),
        .pe1_weight_6(feat_pe1_weight_6), .pe1_weight_7(feat_pe1_weight_7),
        .pe1_weight_8(feat_pe1_weight_8), .pe1_bias(feat_pe1_bias),

        .pe2_weight_0(feat_pe2_weight_0), .pe2_weight_1(feat_pe2_weight_1),
        .pe2_weight_2(feat_pe2_weight_2), .pe2_weight_3(feat_pe2_weight_3),
        .pe2_weight_4(feat_pe2_weight_4), .pe2_weight_5(feat_pe2_weight_5),
        .pe2_weight_6(feat_pe2_weight_6), .pe2_weight_7(feat_pe2_weight_7),
        .pe2_weight_8(feat_pe2_weight_8), .pe2_bias(feat_pe2_bias),

        .pe3_weight_0(feat_pe3_weight_0), .pe3_weight_1(feat_pe3_weight_1),
        .pe3_weight_2(feat_pe3_weight_2), .pe3_weight_3(feat_pe3_weight_3),
        .pe3_weight_4(feat_pe3_weight_4), .pe3_weight_5(feat_pe3_weight_5),
        .pe3_weight_6(feat_pe3_weight_6), .pe3_weight_7(feat_pe3_weight_7),
        .pe3_weight_8(feat_pe3_weight_8), .pe3_bias(feat_pe3_bias)
    );

    weight_buffer #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_gate_weight_buffer (
        .clk(clk),
        .reset(reset),

        .wr_en(gate_weight_wr_en_i),
        .wr_addr(weight_wr_addr),
        .wr_data(weight_wr_data),

        .pe0_weight_0(gate_pe0_weight_0), .pe0_weight_1(gate_pe0_weight_1),
        .pe0_weight_2(gate_pe0_weight_2), .pe0_weight_3(gate_pe0_weight_3),
        .pe0_weight_4(gate_pe0_weight_4), .pe0_weight_5(gate_pe0_weight_5),
        .pe0_weight_6(gate_pe0_weight_6), .pe0_weight_7(gate_pe0_weight_7),
        .pe0_weight_8(gate_pe0_weight_8), .pe0_bias(gate_pe0_bias),

        .pe1_weight_0(gate_pe1_weight_0), .pe1_weight_1(gate_pe1_weight_1),
        .pe1_weight_2(gate_pe1_weight_2), .pe1_weight_3(gate_pe1_weight_3),
        .pe1_weight_4(gate_pe1_weight_4), .pe1_weight_5(gate_pe1_weight_5),
        .pe1_weight_6(gate_pe1_weight_6), .pe1_weight_7(gate_pe1_weight_7),
        .pe1_weight_8(gate_pe1_weight_8), .pe1_bias(gate_pe1_bias),

        .pe2_weight_0(gate_pe2_weight_0), .pe2_weight_1(gate_pe2_weight_1),
        .pe2_weight_2(gate_pe2_weight_2), .pe2_weight_3(gate_pe2_weight_3),
        .pe2_weight_4(gate_pe2_weight_4), .pe2_weight_5(gate_pe2_weight_5),
        .pe2_weight_6(gate_pe2_weight_6), .pe2_weight_7(gate_pe2_weight_7),
        .pe2_weight_8(gate_pe2_weight_8), .pe2_bias(gate_pe2_bias),

        .pe3_weight_0(gate_pe3_weight_0), .pe3_weight_1(gate_pe3_weight_1),
        .pe3_weight_2(gate_pe3_weight_2), .pe3_weight_3(gate_pe3_weight_3),
        .pe3_weight_4(gate_pe3_weight_4), .pe3_weight_5(gate_pe3_weight_5),
        .pe3_weight_6(gate_pe3_weight_6), .pe3_weight_7(gate_pe3_weight_7),
        .pe3_weight_8(gate_pe3_weight_8), .pe3_bias(gate_pe3_bias)
    );

    //=========================================================================
    // 6. Feature PE Array
    //=========================================================================

    wire signed [31:0] feat_conv0, feat_conv1, feat_conv2, feat_conv3;
    wire feat_valid0, feat_valid1, feat_valid2, feat_valid3;
    wire feat_array_valid;

    pe_array #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_feature_pe_array (
        .clk       (clk),
        .reset     (reset),
        .mode_int4 (feat_mode_int4),

        .in_valid  (feat_array_in_valid),
        .line_out0 (line_out0),
        .line_out1 (line_out1),
        .line_out2 (line_out2),

        .pe0_weight_0 (feat_pe0_weight_0), .pe0_weight_1 (feat_pe0_weight_1),
        .pe0_weight_2 (feat_pe0_weight_2), .pe0_weight_3 (feat_pe0_weight_3),
        .pe0_weight_4 (feat_pe0_weight_4), .pe0_weight_5 (feat_pe0_weight_5),
        .pe0_weight_6 (feat_pe0_weight_6), .pe0_weight_7 (feat_pe0_weight_7),
        .pe0_weight_8 (feat_pe0_weight_8), .pe0_bias     (feat_pe0_bias),

        .pe1_weight_0 (feat_pe1_weight_0), .pe1_weight_1 (feat_pe1_weight_1),
        .pe1_weight_2 (feat_pe1_weight_2), .pe1_weight_3 (feat_pe1_weight_3),
        .pe1_weight_4 (feat_pe1_weight_4), .pe1_weight_5 (feat_pe1_weight_5),
        .pe1_weight_6 (feat_pe1_weight_6), .pe1_weight_7 (feat_pe1_weight_7),
        .pe1_weight_8 (feat_pe1_weight_8), .pe1_bias     (feat_pe1_bias),

        .pe2_weight_0 (feat_pe2_weight_0), .pe2_weight_1 (feat_pe2_weight_1),
        .pe2_weight_2 (feat_pe2_weight_2), .pe2_weight_3 (feat_pe2_weight_3),
        .pe2_weight_4 (feat_pe2_weight_4), .pe2_weight_5 (feat_pe2_weight_5),
        .pe2_weight_6 (feat_pe2_weight_6), .pe2_weight_7 (feat_pe2_weight_7),
        .pe2_weight_8 (feat_pe2_weight_8), .pe2_bias     (feat_pe2_bias),

        .pe3_weight_0 (feat_pe3_weight_0), .pe3_weight_1 (feat_pe3_weight_1),
        .pe3_weight_2 (feat_pe3_weight_2), .pe3_weight_3 (feat_pe3_weight_3),
        .pe3_weight_4 (feat_pe3_weight_4), .pe3_weight_5 (feat_pe3_weight_5),
        .pe3_weight_6 (feat_pe3_weight_6), .pe3_weight_7 (feat_pe3_weight_7),
        .pe3_weight_8 (feat_pe3_weight_8), .pe3_bias     (feat_pe3_bias),

        .pe0_conv_out   (feat_conv0), .pe1_conv_out   (feat_conv1),
        .pe2_conv_out   (feat_conv2), .pe3_conv_out   (feat_conv3),

        .pe0_valid_out  (feat_valid0), .pe1_valid_out  (feat_valid1),
        .pe2_valid_out  (feat_valid2), .pe3_valid_out  (feat_valid3),

        .array_valid_out(feat_array_valid)
    );

    //=========================================================================
    // 7. Gate PE Array
    //=========================================================================

    wire signed [31:0] gate_conv0, gate_conv1, gate_conv2, gate_conv3;
    wire gate_valid0, gate_valid1, gate_valid2, gate_valid3;
    wire gate_array_valid;

    pe_array #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_gate_pe_array (
        .clk       (clk),
        .reset     (reset),
        .mode_int4 (gate_mode_int4),

        .in_valid  (gate_array_in_valid),
        .line_out0 (line_out0),
        .line_out1 (line_out1),
        .line_out2 (line_out2),

        .pe0_weight_0 (gate_pe0_weight_0), .pe0_weight_1 (gate_pe0_weight_1),
        .pe0_weight_2 (gate_pe0_weight_2), .pe0_weight_3 (gate_pe0_weight_3),
        .pe0_weight_4 (gate_pe0_weight_4), .pe0_weight_5 (gate_pe0_weight_5),
        .pe0_weight_6 (gate_pe0_weight_6), .pe0_weight_7 (gate_pe0_weight_7),
        .pe0_weight_8 (gate_pe0_weight_8), .pe0_bias     (gate_pe0_bias),

        .pe1_weight_0 (gate_pe1_weight_0), .pe1_weight_1 (gate_pe1_weight_1),
        .pe1_weight_2 (gate_pe1_weight_2), .pe1_weight_3 (gate_pe1_weight_3),
        .pe1_weight_4 (gate_pe1_weight_4), .pe1_weight_5 (gate_pe1_weight_5),
        .pe1_weight_6 (gate_pe1_weight_6), .pe1_weight_7 (gate_pe1_weight_7),
        .pe1_weight_8 (gate_pe1_weight_8), .pe1_bias     (gate_pe1_bias),

        .pe2_weight_0 (gate_pe2_weight_0), .pe2_weight_1 (gate_pe2_weight_1),
        .pe2_weight_2 (gate_pe2_weight_2), .pe2_weight_3 (gate_pe2_weight_3),
        .pe2_weight_4 (gate_pe2_weight_4), .pe2_weight_5 (gate_pe2_weight_5),
        .pe2_weight_6 (gate_pe2_weight_6), .pe2_weight_7 (gate_pe2_weight_7),
        .pe2_weight_8 (gate_pe2_weight_8), .pe2_bias     (gate_pe2_bias),

        .pe3_weight_0 (gate_pe3_weight_0), .pe3_weight_1 (gate_pe3_weight_1),
        .pe3_weight_2 (gate_pe3_weight_2), .pe3_weight_3 (gate_pe3_weight_3),
        .pe3_weight_4 (gate_pe3_weight_4), .pe3_weight_5 (gate_pe3_weight_5),
        .pe3_weight_6 (gate_pe3_weight_6), .pe3_weight_7 (gate_pe3_weight_7),
        .pe3_weight_8 (gate_pe3_weight_8), .pe3_bias     (gate_pe3_bias),

        .pe0_conv_out   (gate_conv0), .pe1_conv_out   (gate_conv1),
        .pe2_conv_out   (gate_conv2), .pe3_conv_out   (gate_conv3),

        .pe0_valid_out  (gate_valid0), .pe1_valid_out  (gate_valid1),
        .pe2_valid_out  (gate_valid2), .pe3_valid_out  (gate_valid3),

        .array_valid_out(gate_array_valid)
    );

    //=========================================================================
    // 8. FSM Controller
    //=========================================================================

    fsm_controller #(
        .DATA_WIDTH      (DATA_WIDTH),
        .LBUF_RD_LATENCY (LBUF_RD_LATENCY),
        .SYNC_FIFO_DEPTH (SYNC_FIFO_DEPTH)
    ) u_fsm_controller (
        .clk              (clk),
        .reset            (reset),

        .layer_start      (layer_start),
        .layer_is_deep    (layer_is_deep),
        .layer_out_pixels (layer_out_pixels),
        .layer_done       (layer_done),

        .feat_lbuf_rd_en  (feat_lbuf_rd_en),
        .feat_line_out0   (line_out0),
        .feat_line_out1   (line_out1),
        .feat_line_out2   (line_out2),

        .gate_lbuf_rd_en  (gate_lbuf_rd_en),
        .gate_line_out0   (line_out0),
        .gate_line_out1   (line_out1),
        .gate_line_out2   (line_out2),

        .feat_in_valid    (feat_in_valid_ctrl),
        .feat_mode_int4   (feat_mode_int4),
        .feat_pe_en       (feat_pe_en),

        .gate_in_valid    (gate_in_valid_ctrl),
        .gate_mode_int4   (gate_mode_int4),
        .gate_pe_en       (gate_pe_en),

        .feat_valid_out   (feat_array_valid),
        .feat_conv_out    (feat_conv0),

        .gate_valid_out   (gate_array_valid),
        .gate_conv_out    (gate_conv0),

        .sync_valid_out   (fsm_sync_valid),
        .feat_conv_sync   (fsm_feat_conv_sync),
        .gate_conv_sync   (fsm_gate_conv_sync)
    );

    //=========================================================================
    // 9. PE output to Activation input conversion
    //=========================================================================

    function automatic signed [ACT_DATA_WIDTH-1:0] conv_to_act;
        input signed [31:0] value;
        reg signed [31:0] shifted;
        begin
            shifted = value >>> CONV_TO_ACT_SHIFT;
            if (shifted > 32'sd32767)
                conv_to_act = 16'sh7fff;
            else if (shifted < -32'sd32768)
                conv_to_act = 16'sh8000;
            else
                conv_to_act = shifted[ACT_DATA_WIDTH-1:0];
        end
    endfunction

    wire signed [ACT_DATA_WIDTH-1:0] feat_act_in0, feat_act_in1, feat_act_in2, feat_act_in3;
    wire signed [ACT_DATA_WIDTH-1:0] gate_act_in0, gate_act_in1, gate_act_in2, gate_act_in3;

    assign feat_act_in0 = conv_to_act(feat_conv0);
    assign feat_act_in1 = conv_to_act(feat_conv1);
    assign feat_act_in2 = conv_to_act(feat_conv2);
    assign feat_act_in3 = conv_to_act(feat_conv3);

    assign gate_act_in0 = conv_to_act(gate_conv0);
    assign gate_act_in1 = conv_to_act(gate_conv1);
    assign gate_act_in2 = conv_to_act(gate_conv2);
    assign gate_act_in3 = conv_to_act(gate_conv3);

    //=========================================================================
    // 10. Activation Units
    //=========================================================================

    wire signed [ACT_DATA_WIDTH-1:0] feat_act0, feat_act1, feat_act2, feat_act3;
    wire signed [ACT_DATA_WIDTH-1:0] gate_act0, gate_act1, gate_act2, gate_act3;

    wire feat_act_valid0, feat_act_valid1, feat_act_valid2, feat_act_valid3;
    wire gate_act_valid0, gate_act_valid1, gate_act_valid2, gate_act_valid3;

    activation_unit #(.DATA_WIDTH(ACT_DATA_WIDTH), .FRAC_WIDTH(FRAC_WIDTH)) u_feat_activation0 (
        .clk(clk), .reset_n(reset_n), .enable(feat_pe_en),
        .track_sel(1'b0), .data_in(feat_act_in0), .valid_in(feat_valid0),
        .data_out(feat_act0), .valid_out(feat_act_valid0)
    );

    activation_unit #(.DATA_WIDTH(ACT_DATA_WIDTH), .FRAC_WIDTH(FRAC_WIDTH)) u_feat_activation1 (
        .clk(clk), .reset_n(reset_n), .enable(feat_pe_en),
        .track_sel(1'b0), .data_in(feat_act_in1), .valid_in(feat_valid1),
        .data_out(feat_act1), .valid_out(feat_act_valid1)
    );

    activation_unit #(.DATA_WIDTH(ACT_DATA_WIDTH), .FRAC_WIDTH(FRAC_WIDTH)) u_feat_activation2 (
        .clk(clk), .reset_n(reset_n), .enable(feat_pe_en),
        .track_sel(1'b0), .data_in(feat_act_in2), .valid_in(feat_valid2),
        .data_out(feat_act2), .valid_out(feat_act_valid2)
    );

    activation_unit #(.DATA_WIDTH(ACT_DATA_WIDTH), .FRAC_WIDTH(FRAC_WIDTH)) u_feat_activation3 (
        .clk(clk), .reset_n(reset_n), .enable(feat_pe_en),
        .track_sel(1'b0), .data_in(feat_act_in3), .valid_in(feat_valid3),
        .data_out(feat_act3), .valid_out(feat_act_valid3)
    );

    activation_unit #(.DATA_WIDTH(ACT_DATA_WIDTH), .FRAC_WIDTH(FRAC_WIDTH)) u_gate_activation0 (
        .clk(clk), .reset_n(reset_n), .enable(gate_pe_en),
        .track_sel(1'b1), .data_in(gate_act_in0), .valid_in(gate_valid0),
        .data_out(gate_act0), .valid_out(gate_act_valid0)
    );

    activation_unit #(.DATA_WIDTH(ACT_DATA_WIDTH), .FRAC_WIDTH(FRAC_WIDTH)) u_gate_activation1 (
        .clk(clk), .reset_n(reset_n), .enable(gate_pe_en),
        .track_sel(1'b1), .data_in(gate_act_in1), .valid_in(gate_valid1),
        .data_out(gate_act1), .valid_out(gate_act_valid1)
    );

    activation_unit #(.DATA_WIDTH(ACT_DATA_WIDTH), .FRAC_WIDTH(FRAC_WIDTH)) u_gate_activation2 (
        .clk(clk), .reset_n(reset_n), .enable(gate_pe_en),
        .track_sel(1'b1), .data_in(gate_act_in2), .valid_in(gate_valid2),
        .data_out(gate_act2), .valid_out(gate_act_valid2)
    );

    activation_unit #(.DATA_WIDTH(ACT_DATA_WIDTH), .FRAC_WIDTH(FRAC_WIDTH)) u_gate_activation3 (
        .clk(clk), .reset_n(reset_n), .enable(gate_pe_en),
        .track_sel(1'b1), .data_in(gate_act_in3), .valid_in(gate_valid3),
        .data_out(gate_act3), .valid_out(gate_act_valid3)
    );

    //=========================================================================
    // 11. Gated Convolution 결과 계산 (channel별 값은 매 사이클 동시 계산됨)
    //=========================================================================

    function automatic signed [ACT_DATA_WIDTH-1:0] sat_act_width;
        input signed [31:0] value;
        begin
            if (value > 32'sd32767)
                sat_act_width = 16'sh7fff;
            else if (value < -32'sd32768)
                sat_act_width = 16'sh8000;
            else
                sat_act_width = value[ACT_DATA_WIDTH-1:0];
        end
    endfunction

    wire signed [(2*ACT_DATA_WIDTH)-1:0] gated_mult0 = feat_act0 * gate_act0;
    wire signed [(2*ACT_DATA_WIDTH)-1:0] gated_mult1 = feat_act1 * gate_act1;
    wire signed [(2*ACT_DATA_WIDTH)-1:0] gated_mult2 = feat_act2 * gate_act2;
    wire signed [(2*ACT_DATA_WIDTH)-1:0] gated_mult3 = feat_act3 * gate_act3;

    wire all_activation_valid =
        feat_act_valid0 & feat_act_valid1 & feat_act_valid2 & feat_act_valid3 &
        gate_act_valid0 & gate_act_valid1 & gate_act_valid2 & gate_act_valid3;

    //=========================================================================
    // 12. [수정] 4채널 출력을 4-cycle 시분할로 직렬화하여 top I/O 절감
    //
    //    4개 채널 결과가 동시에(all_activation_valid) 준비되면 내부 레지스터
    //    4개에 한 번에 래치한 뒤, 이후 4클럭 동안 채널 0->1->2->3 순서로
    //    out_data/out_ch_sel/output_valid에 실어서 내보냅니다.
    //    (주의: 다음 배치가 준비되는 시점까지 이전 배치 전송이 끝나야 하므로,
    //     PE 파이프라인 처리량이 4클럭당 1결과보다 빠르면 send_cnt==4 상태가
    //     아닐 때는 새 래치를 건너뛰게 되어 있습니다. 실사용 시 처리율을
    //     확인해서 필요하면 배압(back-pressure)이나 output FIFO 추가를
    //     검토하세요.)
    //=========================================================================

    reg signed [ACT_DATA_WIDTH-1:0] out_reg0, out_reg1, out_reg2, out_reg3;
    reg [2:0] send_cnt; // 0~3: 채널 전송 중, 4: idle(다음 배치 대기)

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            out_reg0 <= {ACT_DATA_WIDTH{1'b0}};
            out_reg1 <= {ACT_DATA_WIDTH{1'b0}};
            out_reg2 <= {ACT_DATA_WIDTH{1'b0}};
            out_reg3 <= {ACT_DATA_WIDTH{1'b0}};
            send_cnt <= 3'd4;

            out_data     <= {ACT_DATA_WIDTH{1'b0}};
            out_ch_sel   <= 2'd0;
            output_valid <= 1'b0;
        end
        else begin
            output_valid <= 1'b0; // 기본값, 아래에서 조건부로 1로 세팅

            if (all_activation_valid && (send_cnt == 3'd4)) begin
                // 새 결과 배치를 래치하고 채널 0부터 전송 시작
                out_reg0 <= sat_act_width($signed(gated_mult0) >>> FRAC_WIDTH);
                out_reg1 <= sat_act_width($signed(gated_mult1) >>> FRAC_WIDTH);
                out_reg2 <= sat_act_width($signed(gated_mult2) >>> FRAC_WIDTH);
                out_reg3 <= sat_act_width($signed(gated_mult3) >>> FRAC_WIDTH);
                send_cnt <= 3'd0;
            end
            else if (send_cnt < 3'd4) begin
                case (send_cnt[1:0])
                    2'd0: out_data <= out_reg0;
                    2'd1: out_data <= out_reg1;
                    2'd2: out_data <= out_reg2;
                    2'd3: out_data <= out_reg3;
                endcase
                out_ch_sel   <= send_cnt[1:0];
                output_valid <= 1'b1;
                send_cnt     <= send_cnt + 3'd1;
            end
        end
    end

endmodule
