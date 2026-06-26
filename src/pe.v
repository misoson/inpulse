module pe (
    input  wire clk,
    input  wire rst_n,
    input  wire valid_in,

    input  wire mode_int4,

    input  wire signed [7:0] p0, p1, p2,
    input  wire signed [7:0] p3, p4, p5,
    input  wire signed [7:0] p6, p7, p8,

    input  wire signed [7:0] w0, w1, w2,
    input  wire signed [7:0] w3, w4, w5,
    input  wire signed [7:0] w6, w7, w8,

    input  wire signed [31:0] bias,

    output reg  signed [31:0] conv_out,
    output reg  valid_out
);

endmodule