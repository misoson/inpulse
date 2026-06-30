module pe_input (
    input  wire        clk,
    input  wire        reset,
    input  wire        in_valid,
    input  wire        mode_int4,

    input  wire [7:0]  line_out0,
    input  wire [7:0]  line_out1,
    input  wire [7:0]  line_out2,

    output reg  [7:0]  pe_pixel_0,
    output reg  [7:0]  pe_pixel_1,
    output reg  [7:0]  pe_pixel_2,
    output reg  [7:0]  pe_pixel_3,
    output reg  [7:0]  pe_pixel_4,
    output reg  [7:0]  pe_pixel_5,
    output reg  [7:0]  pe_pixel_6,
    output reg  [7:0]  pe_pixel_7,
    output reg  [7:0]  pe_pixel_8,

    output reg         out_valid
);

reg [7:0] row0_shift0, row0_shift1, row0_shift2;
reg [7:0] row1_shift0, row1_shift1, row1_shift2;
reg [7:0] row2_shift0, row2_shift1, row2_shift2;

reg [1:0] valid_count;

wire [7:0] line0_data;
wire [7:0] line1_data;
wire [7:0] line2_data;

assign line0_data = mode_int4 ? {4'd0, line_out0[3:0]} : line_out0;
assign line1_data = mode_int4 ? {4'd0, line_out1[3:0]} : line_out1;
assign line2_data = mode_int4 ? {4'd0, line_out2[3:0]} : line_out2;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        row0_shift0 <= 8'd0;
        row0_shift1 <= 8'd0;
        row0_shift2 <= 8'd0;

        row1_shift0 <= 8'd0;
        row1_shift1 <= 8'd0;
        row1_shift2 <= 8'd0;

        row2_shift0 <= 8'd0;
        row2_shift1 <= 8'd0;
        row2_shift2 <= 8'd0;

        pe_pixel_0 <= 8'd0;
        pe_pixel_1 <= 8'd0;
        pe_pixel_2 <= 8'd0;
        pe_pixel_3 <= 8'd0;
        pe_pixel_4 <= 8'd0;
        pe_pixel_5 <= 8'd0;
        pe_pixel_6 <= 8'd0;
        pe_pixel_7 <= 8'd0;
        pe_pixel_8 <= 8'd0;

        valid_count <= 2'd0;
        out_valid   <= 1'b0;
    end
    else begin
        if (in_valid) begin
            row0_shift2 <= row0_shift1;
            row0_shift1 <= row0_shift0;
            row0_shift0 <= line0_data;

            row1_shift2 <= row1_shift1;
            row1_shift1 <= row1_shift0;
            row1_shift0 <= line1_data;

            row2_shift2 <= row2_shift1;
            row2_shift1 <= row2_shift0;
            row2_shift0 <= line2_data;

            if (valid_count < 2'd2) begin
                valid_count <= valid_count + 1'b1;
                out_valid <= 1'b0;
            end
            else begin
                out_valid <= 1'b1;
            end

            pe_pixel_0 <= row0_shift2;
            pe_pixel_1 <= row0_shift1;
            pe_pixel_2 <= row0_shift0;

            pe_pixel_3 <= row1_shift2;
            pe_pixel_4 <= row1_shift1;
            pe_pixel_5 <= row1_shift0;

            pe_pixel_6 <= row2_shift2;
            pe_pixel_7 <= row2_shift1;
            pe_pixel_8 <= row2_shift0;
        end
        else begin
            out_valid <= 1'b0;
        end
    end
end

endmodule