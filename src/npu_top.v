`timescale 1ns / 1ps

//=============================================================================
// File        : npu_top.v
// Description : Draft top module for Gated Convolution NPU
//
// Current integration policy
//   1) One line_buffer is shared by Feature/Gate tracks.
//   2) Two pe_array instances are used because Feature/Gate precision differs.
//      - Feature: initial layer INT8, deep layer INT4
//      - Gate   : always INT4
//   3) Weight/Bias are temporarily provided through flattened top-level ports.
//      Replace these ports with the parameter/weight-bias module when finalized.
//   4) Existing fsm_controller is used for layer control and completion counting.
//   5) PE 32-bit output is converted to signed 16-bit Q8.8 before activation.
//      CONV_TO_ACT_SHIFT must be determined from quantization/golden data.
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

    // Temporary Feature weight/bias interface
    // Weight layout:
    // PE0 = weight 0~8
    // PE1 = weight 9~17
    // PE2 = weight 18~26
    // PE3 = weight 27~35
    input wire signed [(4*9*DATA_WIDTH)-1:0] feat_weights_flat,
    input wire signed [(4*32)-1:0]           feat_biases_flat,

    // Temporary Gate weight/bias interface
    input wire signed [(4*9*DATA_WIDTH)-1:0] gate_weights_flat,
    input wire signed [(4*32)-1:0]           gate_biases_flat,

    // Four output channels, signed Q8.8
    output reg signed [ACT_DATA_WIDTH-1:0] out_ch0,
    output reg signed [ACT_DATA_WIDTH-1:0] out_ch1,
    output reg signed [ACT_DATA_WIDTH-1:0] out_ch2,
    output reg signed [ACT_DATA_WIDTH-1:0] out_ch3,
    output reg                             output_valid
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
    wire signed [31:0]  fsm_feat_conv_sync;
    wire signed [31:0]  fsm_gate_conv_sync;

    //=========================================================================
    // 3. Shared Line Buffer
    //
    // Current line_buffer does not have an explicit rd_en input.
    // Therefore, FSM read enable and external valid are combined and connected
    // to photo_data_valid.
    //=========================================================================

    wire lbuf_stream_enable;

    assign lbuf_stream_enable =
        photo_data_valid &
        feat_lbuf_rd_en &
        gate_lbuf_rd_en;

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

    // PE input valid:
    // FSM latency correction + line buffer valid
    wire feat_array_in_valid;
    wire gate_array_in_valid;

    assign feat_array_in_valid =
        feat_in_valid_ctrl & line_data_valid;

    assign gate_array_in_valid =
        gate_in_valid_ctrl & line_data_valid;

    //=========================================================================
    // 4. Feature PE Array
    //=========================================================================

    wire signed [31:0] feat_conv0;
    wire signed [31:0] feat_conv1;
    wire signed [31:0] feat_conv2;
    wire signed [31:0] feat_conv3;

    wire feat_valid0;
    wire feat_valid1;
    wire feat_valid2;
    wire feat_valid3;

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

        // PE0
        .pe0_weight_0 (
            $signed(feat_weights_flat[(0*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_1 (
            $signed(feat_weights_flat[(1*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_2 (
            $signed(feat_weights_flat[(2*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_3 (
            $signed(feat_weights_flat[(3*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_4 (
            $signed(feat_weights_flat[(4*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_5 (
            $signed(feat_weights_flat[(5*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_6 (
            $signed(feat_weights_flat[(6*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_7 (
            $signed(feat_weights_flat[(7*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_8 (
            $signed(feat_weights_flat[(8*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_bias (
            $signed(feat_biases_flat[(0*32) +: 32])
        ),

        // PE1
        .pe1_weight_0 (
            $signed(feat_weights_flat[(9*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_1 (
            $signed(feat_weights_flat[(10*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_2 (
            $signed(feat_weights_flat[(11*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_3 (
            $signed(feat_weights_flat[(12*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_4 (
            $signed(feat_weights_flat[(13*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_5 (
            $signed(feat_weights_flat[(14*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_6 (
            $signed(feat_weights_flat[(15*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_7 (
            $signed(feat_weights_flat[(16*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_8 (
            $signed(feat_weights_flat[(17*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_bias (
            $signed(feat_biases_flat[(1*32) +: 32])
        ),

        // PE2
        .pe2_weight_0 (
            $signed(feat_weights_flat[(18*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_1 (
            $signed(feat_weights_flat[(19*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_2 (
            $signed(feat_weights_flat[(20*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_3 (
            $signed(feat_weights_flat[(21*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_4 (
            $signed(feat_weights_flat[(22*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_5 (
            $signed(feat_weights_flat[(23*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_6 (
            $signed(feat_weights_flat[(24*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_7 (
            $signed(feat_weights_flat[(25*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_8 (
            $signed(feat_weights_flat[(26*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_bias (
            $signed(feat_biases_flat[(2*32) +: 32])
        ),

        // PE3
        .pe3_weight_0 (
            $signed(feat_weights_flat[(27*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_1 (
            $signed(feat_weights_flat[(28*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_2 (
            $signed(feat_weights_flat[(29*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_3 (
            $signed(feat_weights_flat[(30*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_4 (
            $signed(feat_weights_flat[(31*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_5 (
            $signed(feat_weights_flat[(32*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_6 (
            $signed(feat_weights_flat[(33*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_7 (
            $signed(feat_weights_flat[(34*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_8 (
            $signed(feat_weights_flat[(35*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_bias (
            $signed(feat_biases_flat[(3*32) +: 32])
        ),

        .pe0_conv_out   (feat_conv0),
        .pe1_conv_out   (feat_conv1),
        .pe2_conv_out   (feat_conv2),
        .pe3_conv_out   (feat_conv3),

        .pe0_valid_out  (feat_valid0),
        .pe1_valid_out  (feat_valid1),
        .pe2_valid_out  (feat_valid2),
        .pe3_valid_out  (feat_valid3),

        .array_valid_out(feat_array_valid)
    );

    //=========================================================================
    // 5. Gate PE Array
    //=========================================================================

    wire signed [31:0] gate_conv0;
    wire signed [31:0] gate_conv1;
    wire signed [31:0] gate_conv2;
    wire signed [31:0] gate_conv3;

    wire gate_valid0;
    wire gate_valid1;
    wire gate_valid2;
    wire gate_valid3;

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

        // PE0
        .pe0_weight_0 (
            $signed(gate_weights_flat[(0*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_1 (
            $signed(gate_weights_flat[(1*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_2 (
            $signed(gate_weights_flat[(2*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_3 (
            $signed(gate_weights_flat[(3*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_4 (
            $signed(gate_weights_flat[(4*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_5 (
            $signed(gate_weights_flat[(5*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_6 (
            $signed(gate_weights_flat[(6*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_7 (
            $signed(gate_weights_flat[(7*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_weight_8 (
            $signed(gate_weights_flat[(8*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe0_bias (
            $signed(gate_biases_flat[(0*32) +: 32])
        ),

        // PE1
        .pe1_weight_0 (
            $signed(gate_weights_flat[(9*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_1 (
            $signed(gate_weights_flat[(10*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_2 (
            $signed(gate_weights_flat[(11*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_3 (
            $signed(gate_weights_flat[(12*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_4 (
            $signed(gate_weights_flat[(13*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_5 (
            $signed(gate_weights_flat[(14*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_6 (
            $signed(gate_weights_flat[(15*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_7 (
            $signed(gate_weights_flat[(16*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_weight_8 (
            $signed(gate_weights_flat[(17*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe1_bias (
            $signed(gate_biases_flat[(1*32) +: 32])
        ),

        // PE2
        .pe2_weight_0 (
            $signed(gate_weights_flat[(18*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_1 (
            $signed(gate_weights_flat[(19*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_2 (
            $signed(gate_weights_flat[(20*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_3 (
            $signed(gate_weights_flat[(21*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_4 (
            $signed(gate_weights_flat[(22*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_5 (
            $signed(gate_weights_flat[(23*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_6 (
            $signed(gate_weights_flat[(24*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_7 (
            $signed(gate_weights_flat[(25*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_weight_8 (
            $signed(gate_weights_flat[(26*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe2_bias (
            $signed(gate_biases_flat[(2*32) +: 32])
        ),

        // PE3
        .pe3_weight_0 (
            $signed(gate_weights_flat[(27*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_1 (
            $signed(gate_weights_flat[(28*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_2 (
            $signed(gate_weights_flat[(29*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_3 (
            $signed(gate_weights_flat[(30*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_4 (
            $signed(gate_weights_flat[(31*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_5 (
            $signed(gate_weights_flat[(32*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_6 (
            $signed(gate_weights_flat[(33*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_7 (
            $signed(gate_weights_flat[(34*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_weight_8 (
            $signed(gate_weights_flat[(35*DATA_WIDTH) +: DATA_WIDTH])
        ),
        .pe3_bias (
            $signed(gate_biases_flat[(3*32) +: 32])
        ),

        .pe0_conv_out   (gate_conv0),
        .pe1_conv_out   (gate_conv1),
        .pe2_conv_out   (gate_conv2),
        .pe3_conv_out   (gate_conv3),

        .pe0_valid_out  (gate_valid0),
        .pe1_valid_out  (gate_valid1),
        .pe2_valid_out  (gate_valid2),
        .pe3_valid_out  (gate_valid3),

        .array_valid_out(gate_array_valid)
    );

    //=========================================================================
    // 6. FSM Controller
    //
    // Channel 0 is connected as representative Feature/Gate output.
    // All PEs in one array currently have identical pipeline latency.
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

        .feat_valid_out   (feat_valid0),
        .feat_conv_out    (feat_conv0),

        .gate_valid_out   (gate_valid0),
        .gate_conv_out    (gate_conv0),

        .sync_valid_out   (fsm_sync_valid),
        .feat_conv_sync   (fsm_feat_conv_sync),
        .gate_conv_sync   (fsm_gate_conv_sync)
    );

    //=========================================================================
    // 7. PE output to Activation input conversion
    //
    // Converts signed 32-bit PE output into signed 16-bit activation input.
    // CONV_TO_ACT_SHIFT is a temporary value.
    // It must be determined using actual quantization scale.
    //=========================================================================

    function signed [ACT_DATA_WIDTH-1:0] conv_to_act;

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

    wire signed [ACT_DATA_WIDTH-1:0] feat_act_in0;
    wire signed [ACT_DATA_WIDTH-1:0] feat_act_in1;
    wire signed [ACT_DATA_WIDTH-1:0] feat_act_in2;
    wire signed [ACT_DATA_WIDTH-1:0] feat_act_in3;

    wire signed [ACT_DATA_WIDTH-1:0] gate_act_in0;
    wire signed [ACT_DATA_WIDTH-1:0] gate_act_in1;
    wire signed [ACT_DATA_WIDTH-1:0] gate_act_in2;
    wire signed [ACT_DATA_WIDTH-1:0] gate_act_in3;

    assign feat_act_in0 = conv_to_act(feat_conv0);
    assign feat_act_in1 = conv_to_act(feat_conv1);
    assign feat_act_in2 = conv_to_act(feat_conv2);
    assign feat_act_in3 = conv_to_act(feat_conv3);

    assign gate_act_in0 = conv_to_act(gate_conv0);
    assign gate_act_in1 = conv_to_act(gate_conv1);
    assign gate_act_in2 = conv_to_act(gate_conv2);
    assign gate_act_in3 = conv_to_act(gate_conv3);

    //=========================================================================
    // 8. Activation Units
    //
    // Feature Track: ReLU
    // Gate Track   : Sigmoid PLAN
    //=========================================================================

    wire signed [ACT_DATA_WIDTH-1:0] feat_act0;
    wire signed [ACT_DATA_WIDTH-1:0] feat_act1;
    wire signed [ACT_DATA_WIDTH-1:0] feat_act2;
    wire signed [ACT_DATA_WIDTH-1:0] feat_act3;

    wire signed [ACT_DATA_WIDTH-1:0] gate_act0;
    wire signed [ACT_DATA_WIDTH-1:0] gate_act1;
    wire signed [ACT_DATA_WIDTH-1:0] gate_act2;
    wire signed [ACT_DATA_WIDTH-1:0] gate_act3;

    wire feat_act_valid0;
    wire feat_act_valid1;
    wire feat_act_valid2;
    wire feat_act_valid3;

    wire gate_act_valid0;
    wire gate_act_valid1;
    wire gate_act_valid2;
    wire gate_act_valid3;

    activation_unit #(
        .DATA_WIDTH (ACT_DATA_WIDTH),
        .FRAC_WIDTH (FRAC_WIDTH)
    ) u_feat_activation0 (
        .clk       (clk),
        .reset_n   (reset_n),
        .enable    (feat_pe_en),

        .track_sel (1'b0),
        .data_in   (feat_act_in0),
        .valid_in  (feat_valid0),

        .data_out  (feat_act0),
        .valid_out (feat_act_valid0)
    );

    activation_unit #(
        .DATA_WIDTH (ACT_DATA_WIDTH),
        .FRAC_WIDTH (FRAC_WIDTH)
    ) u_feat_activation1 (
        .clk       (clk),
        .reset_n   (reset_n),
        .enable    (feat_pe_en),

        .track_sel (1'b0),
        .data_in   (feat_act_in1),
        .valid_in  (feat_valid1),

        .data_out  (feat_act1),
        .valid_out (feat_act_valid1)
    );

    activation_unit #(
        .DATA_WIDTH (ACT_DATA_WIDTH),
        .FRAC_WIDTH (FRAC_WIDTH)
    ) u_feat_activation2 (
        .clk       (clk),
        .reset_n   (reset_n),
        .enable    (feat_pe_en),

        .track_sel (1'b0),
        .data_in   (feat_act_in2),
        .valid_in  (feat_valid2),

        .data_out  (feat_act2),
        .valid_out (feat_act_valid2)
    );

    activation_unit #(
        .DATA_WIDTH (ACT_DATA_WIDTH),
        .FRAC_WIDTH (FRAC_WIDTH)
    ) u_feat_activation3 (
        .clk       (clk),
        .reset_n   (reset_n),
        .enable    (feat_pe_en),

        .track_sel (1'b0),
        .data_in   (feat_act_in3),
        .valid_in  (feat_valid3),

        .data_out  (feat_act3),
        .valid_out (feat_act_valid3)
    );

    activation_unit #(
        .DATA_WIDTH (ACT_DATA_WIDTH),
        .FRAC_WIDTH (FRAC_WIDTH)
    ) u_gate_activation0 (
        .clk       (clk),
        .reset_n   (reset_n),
        .enable    (gate_pe_en),

        .track_sel (1'b1),
        .data_in   (gate_act_in0),
        .valid_in  (gate_valid0),

        .data_out  (gate_act0),
        .valid_out (gate_act_valid0)
    );

    activation_unit #(
        .DATA_WIDTH (ACT_DATA_WIDTH),
        .FRAC_WIDTH (FRAC_WIDTH)
    ) u_gate_activation1 (
        .clk       (clk),
        .reset_n   (reset_n),
        .enable    (gate_pe_en),

        .track_sel (1'b1),
        .data_in   (gate_act_in1),
        .valid_in  (gate_valid1),

        .data_out  (gate_act1),
        .valid_out (gate_act_valid1)
    );

    activation_unit #(
        .DATA_WIDTH (ACT_DATA_WIDTH),
        .FRAC_WIDTH (FRAC_WIDTH)
    ) u_gate_activation2 (
        .clk       (clk),
        .reset_n   (reset_n),
        .enable    (gate_pe_en),

        .track_sel (1'b1),
        .data_in   (gate_act_in2),
        .valid_in  (gate_valid2),

        .data_out  (gate_act2),
        .valid_out (gate_act_valid2)
    );

    activation_unit #(
        .DATA_WIDTH (ACT_DATA_WIDTH),
        .FRAC_WIDTH (FRAC_WIDTH)
    ) u_gate_activation3 (
        .clk       (clk),
        .reset_n   (reset_n),
        .enable    (gate_pe_en),

        .track_sel (1'b1),
        .data_in   (gate_act_in3),
        .valid_in  (gate_valid3),

        .data_out  (gate_act3),
        .valid_out (gate_act_valid3)
    );

    //=========================================================================
    // 9. Gated Convolution Output
    //
    // Q8.8 x Q8.8 = Q16.16
    // Arithmetic right shift by FRAC_WIDTH restores Q8.8.
    //=========================================================================

    function signed [ACT_DATA_WIDTH-1:0] sat_act_width;

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

    wire signed [(2*ACT_DATA_WIDTH)-1:0] gated_mult0;
    wire signed [(2*ACT_DATA_WIDTH)-1:0] gated_mult1;
    wire signed [(2*ACT_DATA_WIDTH)-1:0] gated_mult2;
    wire signed [(2*ACT_DATA_WIDTH)-1:0] gated_mult3;

    assign gated_mult0 = feat_act0 * gate_act0;
    assign gated_mult1 = feat_act1 * gate_act1;
    assign gated_mult2 = feat_act2 * gate_act2;
    assign gated_mult3 = feat_act3 * gate_act3;

    wire all_activation_valid;

    assign all_activation_valid =
        feat_act_valid0 &
        feat_act_valid1 &
        feat_act_valid2 &
        feat_act_valid3 &
        gate_act_valid0 &
        gate_act_valid1 &
        gate_act_valid2 &
        gate_act_valid3;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            out_ch0      <= {ACT_DATA_WIDTH{1'b0}};
            out_ch1      <= {ACT_DATA_WIDTH{1'b0}};
            out_ch2      <= {ACT_DATA_WIDTH{1'b0}};
            out_ch3      <= {ACT_DATA_WIDTH{1'b0}};
            output_valid <= 1'b0;
        end

        else begin
            output_valid <= all_activation_valid;

            if (all_activation_valid) begin
                out_ch0 <= sat_act_width(
                    $signed(gated_mult0) >>> FRAC_WIDTH
                );

                out_ch1 <= sat_act_width(
                    $signed(gated_mult1) >>> FRAC_WIDTH
                );

                out_ch2 <= sat_act_width(
                    $signed(gated_mult2) >>> FRAC_WIDTH
                );

                out_ch3 <= sat_act_width(
                    $signed(gated_mult3) >>> FRAC_WIDTH
                );
            end
        end
    end

endmodule