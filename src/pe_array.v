`timescale 1ns / 1ps

module pe_array #(
    parameter DATA_WIDTH = 8
)(
    input wire clk,
    input wire reset,          // active-high reset
    input wire mode_int4,      // 0: INT8, 1: INT4

    // from line_buffer
    input wire in_valid,
    input wire [DATA_WIDTH-1:0] line_out0,
    input wire [DATA_WIDTH-1:0] line_out1,
    input wire [DATA_WIDTH-1:0] line_out2,

    // PE0 weights / bias
    input wire signed [DATA_WIDTH-1:0] pe0_weight_0,
    input wire signed [DATA_WIDTH-1:0] pe0_weight_1,
    input wire signed [DATA_WIDTH-1:0] pe0_weight_2,
    input wire signed [DATA_WIDTH-1:0] pe0_weight_3,
    input wire signed [DATA_WIDTH-1:0] pe0_weight_4,
    input wire signed [DATA_WIDTH-1:0] pe0_weight_5,
    input wire signed [DATA_WIDTH-1:0] pe0_weight_6,
    input wire signed [DATA_WIDTH-1:0] pe0_weight_7,
    input wire signed [DATA_WIDTH-1:0] pe0_weight_8,
    input wire signed [31:0] pe0_bias,

    // PE1 weights / bias
    input wire signed [DATA_WIDTH-1:0] pe1_weight_0,
    input wire signed [DATA_WIDTH-1:0] pe1_weight_1,
    input wire signed [DATA_WIDTH-1:0] pe1_weight_2,
    input wire signed [DATA_WIDTH-1:0] pe1_weight_3,
    input wire signed [DATA_WIDTH-1:0] pe1_weight_4,
    input wire signed [DATA_WIDTH-1:0] pe1_weight_5,
    input wire signed [DATA_WIDTH-1:0] pe1_weight_6,
    input wire signed [DATA_WIDTH-1:0] pe1_weight_7,
    input wire signed [DATA_WIDTH-1:0] pe1_weight_8,
    input wire signed [31:0] pe1_bias,

    // PE2 weights / bias
    input wire signed [DATA_WIDTH-1:0] pe2_weight_0,
    input wire signed [DATA_WIDTH-1:0] pe2_weight_1,
    input wire signed [DATA_WIDTH-1:0] pe2_weight_2,
    input wire signed [DATA_WIDTH-1:0] pe2_weight_3,
    input wire signed [DATA_WIDTH-1:0] pe2_weight_4,
    input wire signed [DATA_WIDTH-1:0] pe2_weight_5,
    input wire signed [DATA_WIDTH-1:0] pe2_weight_6,
    input wire signed [DATA_WIDTH-1:0] pe2_weight_7,
    input wire signed [DATA_WIDTH-1:0] pe2_weight_8,
    input wire signed [31:0] pe2_bias,

    // PE3 weights / bias
    input wire signed [DATA_WIDTH-1:0] pe3_weight_0,
    input wire signed [DATA_WIDTH-1:0] pe3_weight_1,
    input wire signed [DATA_WIDTH-1:0] pe3_weight_2,
    input wire signed [DATA_WIDTH-1:0] pe3_weight_3,
    input wire signed [DATA_WIDTH-1:0] pe3_weight_4,
    input wire signed [DATA_WIDTH-1:0] pe3_weight_5,
    input wire signed [DATA_WIDTH-1:0] pe3_weight_6,
    input wire signed [DATA_WIDTH-1:0] pe3_weight_7,
    input wire signed [DATA_WIDTH-1:0] pe3_weight_8,
    input wire signed [31:0] pe3_bias,

    // outputs to activation / next stage
    output wire signed [31:0] pe0_conv_out,
    output wire signed [31:0] pe1_conv_out,
    output wire signed [31:0] pe2_conv_out,
    output wire signed [31:0] pe3_conv_out,

    output wire pe0_valid_out,
    output wire pe1_valid_out,
    output wire pe2_valid_out,
    output wire pe3_valid_out,

    // all PE outputs valid at same timing
    output wire array_valid_out
);

    pe #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_pe0 (
        .clk(clk),
        .reset(reset),
        .mode_int4(mode_int4),
        .in_valid(in_valid),

        .line_out0(line_out0),
        .line_out1(line_out1),
        .line_out2(line_out2),

        .weight_0(pe0_weight_0),
        .weight_1(pe0_weight_1),
        .weight_2(pe0_weight_2),
        .weight_3(pe0_weight_3),
        .weight_4(pe0_weight_4),
        .weight_5(pe0_weight_5),
        .weight_6(pe0_weight_6),
        .weight_7(pe0_weight_7),
        .weight_8(pe0_weight_8),
        .bias(pe0_bias),

        .conv_out(pe0_conv_out),
        .valid_out(pe0_valid_out)
    );

    pe #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_pe1 (
        .clk(clk),
        .reset(reset),
        .mode_int4(mode_int4),
        .in_valid(in_valid),

        .line_out0(line_out0),
        .line_out1(line_out1),
        .line_out2(line_out2),

        .weight_0(pe1_weight_0),
        .weight_1(pe1_weight_1),
        .weight_2(pe1_weight_2),
        .weight_3(pe1_weight_3),
        .weight_4(pe1_weight_4),
        .weight_5(pe1_weight_5),
        .weight_6(pe1_weight_6),
        .weight_7(pe1_weight_7),
        .weight_8(pe1_weight_8),
        .bias(pe1_bias),

        .conv_out(pe1_conv_out),
        .valid_out(pe1_valid_out)
    );

    pe #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_pe2 (
        .clk(clk),
        .reset(reset),
        .mode_int4(mode_int4),
        .in_valid(in_valid),

        .line_out0(line_out0),
        .line_out1(line_out1),
        .line_out2(line_out2),

        .weight_0(pe2_weight_0),
        .weight_1(pe2_weight_1),
        .weight_2(pe2_weight_2),
        .weight_3(pe2_weight_3),
        .weight_4(pe2_weight_4),
        .weight_5(pe2_weight_5),
        .weight_6(pe2_weight_6),
        .weight_7(pe2_weight_7),
        .weight_8(pe2_weight_8),
        .bias(pe2_bias),

        .conv_out(pe2_conv_out),
        .valid_out(pe2_valid_out)
    );

    pe #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_pe3 (
        .clk(clk),
        .reset(reset),
        .mode_int4(mode_int4),
        .in_valid(in_valid),

        .line_out0(line_out0),
        .line_out1(line_out1),
        .line_out2(line_out2),

        .weight_0(pe3_weight_0),
        .weight_1(pe3_weight_1),
        .weight_2(pe3_weight_2),
        .weight_3(pe3_weight_3),
        .weight_4(pe3_weight_4),
        .weight_5(pe3_weight_5),
        .weight_6(pe3_weight_6),
        .weight_7(pe3_weight_7),
        .weight_8(pe3_weight_8),
        .bias(pe3_bias),

        .conv_out(pe3_conv_out),
        .valid_out(pe3_valid_out)
    );

    assign array_valid_out = pe0_valid_out & pe1_valid_out & pe2_valid_out & pe3_valid_out;

endmodule