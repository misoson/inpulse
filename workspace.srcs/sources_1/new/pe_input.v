// 변경 사항
// 1. DATA_WIDTH 파라미터 통일
// 2. mode_int4 동작 시 데이터 비트수에 따른 유연한 동작을 위해 하드코딩 수정
// 3. 리셋 값이 데이터 폭에 상관 없이 적용되도록 8'd0 -> 0 으로 통일

module pe_input #(
    parameter DATA_WIDTH=8  // 파라미터 추가
)(
    input  wire        clk,
    input  wire        reset,
    // line_buffer.v 의 line_data_valid 와 연결
    input  wire        in_valid,
    input  wire        mode_int4,

    // line_buffer.v 의 출력과 연결
    input  wire [DATA_WIDTH-1:0]  line_out0,
    input  wire [DATA_WIDTH-1:0]  line_out1,
    input  wire [DATA_WIDTH-1:0]  line_out2,

    output reg  [DATA_WIDTH-1:0]  pe_pixel_0,
    output reg  [DATA_WIDTH-1:0]  pe_pixel_1,
    output reg  [DATA_WIDTH-1:0]  pe_pixel_2,
    output reg  [DATA_WIDTH-1:0]  pe_pixel_3,
    output reg  [DATA_WIDTH-1:0]  pe_pixel_4,
    output reg  [DATA_WIDTH-1:0]  pe_pixel_5,
    output reg  [DATA_WIDTH-1:0]  pe_pixel_6,
    output reg  [DATA_WIDTH-1:0]  pe_pixel_7,
    output reg  [DATA_WIDTH-1:0]  pe_pixel_8,

    output reg         out_valid
);

reg [DATA_WIDTH-1:0] row0_shift0, row0_shift1, row0_shift2;
reg [DATA_WIDTH-1:0] row1_shift0, row1_shift1, row1_shift2;
reg [DATA_WIDTH-1:0] row2_shift0, row2_shift1, row2_shift2;

reg [1:0] valid_count;

wire [DATA_WIDTH-1:0] line0_data;
wire [DATA_WIDTH-1:0] line1_data;
wire [DATA_WIDTH-1:0] line2_data;

// 수정: DATA_WIDTH 에 맞추어 0 패딩
assign line0_data = mode_int4 ? { {(DATA_WIDTH-4){1'b0}}, line_out0[3:0] } : line_out0;
assign line1_data = mode_int4 ? { {(DATA_WIDTH-4){1'b0}}, line_out1[3:0] } : line_out1;
assign line2_data = mode_int4 ? { {(DATA_WIDTH-4){1'b0}}, line_out2[3:0] } : line_out2;

always @(posedge clk or posedge reset) begin
    if (reset) begin
    // DATA_WIDTH 에 상관 없이 적용되도록 0으로 통일
        row0_shift0 <= 0;   row0_shift1 <= 0;   row0_shift2 <= 0;
        row1_shift0 <= 0;   row1_shift1 <= 0;   row1_shift2 <= 0;
        row2_shift0 <= 0;   row2_shift1 <= 0;   row2_shift2 <= 0;

        pe_pixel_0 <= 0;   pe_pixel_1 <= 0;   pe_pixel_2 <= 0;
        pe_pixel_3 <= 0;   pe_pixel_4 <= 0;   pe_pixel_5 <= 0;
        pe_pixel_6 <= 0;   pe_pixel_7 <= 0;   pe_pixel_8 <= 0;

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