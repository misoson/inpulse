module pe_input (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,

    input  wire        mode_int4,   // 0: INT8, 1: INT4

    input  wire [7:0]  pixel_0,
    input  wire [7:0]  pixel_1,
    input  wire [7:0]  pixel_2,
    input  wire [7:0]  pixel_3,
    input  wire [7:0]  pixel_4,
    input  wire [7:0]  pixel_5,
    input  wire [7:0]  pixel_6,
    input  wire [7:0]  pixel_7,
    input  wire [7:0]  pixel_8,

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

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pe_pixel_0 <= 8'd0;
        pe_pixel_1 <= 8'd0;
        pe_pixel_2 <= 8'd0;
        pe_pixel_3 <= 8'd0;
        pe_pixel_4 <= 8'd0;
        pe_pixel_5 <= 8'd0;
        pe_pixel_6 <= 8'd0;
        pe_pixel_7 <= 8'd0;
        pe_pixel_8 <= 8'd0;
        out_valid  <= 1'b0;
    end
    else begin
        out_valid <= in_valid;

        if (in_valid) begin
            if (mode_int4) begin
                // INT4 mode: 하위 4bit만 사용, 상위 4bit는 0으로 채움
                pe_pixel_0 <= {4'd0, pixel_0[3:0]};
                pe_pixel_1 <= {4'd0, pixel_1[3:0]};
                pe_pixel_2 <= {4'd0, pixel_2[3:0]};
                pe_pixel_3 <= {4'd0, pixel_3[3:0]};
                pe_pixel_4 <= {4'd0, pixel_4[3:0]};
                pe_pixel_5 <= {4'd0, pixel_5[3:0]};
                pe_pixel_6 <= {4'd0, pixel_6[3:0]};
                pe_pixel_7 <= {4'd0, pixel_7[3:0]};
                pe_pixel_8 <= {4'd0, pixel_8[3:0]};
            end
            else begin
                // INT8 mode
                pe_pixel_0 <= pixel_0;
                pe_pixel_1 <= pixel_1;
                pe_pixel_2 <= pixel_2;
                pe_pixel_3 <= pixel_3;
                pe_pixel_4 <= pixel_4;
                pe_pixel_5 <= pixel_5;
                pe_pixel_6 <= pixel_6;
                pe_pixel_7 <= pixel_7;
                pe_pixel_8 <= pixel_8;
            end
        end
    end
end

endmodule