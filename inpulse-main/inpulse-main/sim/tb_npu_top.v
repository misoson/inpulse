`timescale 1ns / 1ps

module tb_npu_top;

    //=========================================================================
    // 1. Parameters
    //=========================================================================
    parameter DATA_WIDTH        = 8;
    parameter LINE_LENGTH       = 1024;
    parameter ACT_DATA_WIDTH    = 16;
    parameter FRAC_WIDTH        = 8;

    //=========================================================================
    // 2. Signals
    //=========================================================================
    reg clk;
    reg reset;

    reg        layer_start;
    reg        layer_is_deep;
    reg [15:0] layer_out_pixels;
    wire       layer_done;

    reg                  photo_data_valid;
    reg [DATA_WIDTH-1:0] pixel_data_in;

    // [수정됨] 통합된 가중치 버퍼 입력 신호
    reg        weight_wr_en;
    reg        weight_wr_target;
    reg [3:0]  weight_wr_addr;
    reg [31:0] weight_wr_data;

    // [수정됨] 시분할 1가닥 출력 신호
    wire signed [ACT_DATA_WIDTH-1:0] out_data;
    wire [1:0]                       out_ch_sel;
    wire                             output_valid;

    integer i;

    //=========================================================================
    // 3. DUT (Device Under Test) Instantiation
    //=========================================================================
    npu_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .LINE_LENGTH(LINE_LENGTH),
        .ACT_DATA_WIDTH(ACT_DATA_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    ) uut (
        .clk(clk),
        .reset(reset),

        .layer_start(layer_start),
        .layer_is_deep(layer_is_deep),
        .layer_out_pixels(layer_out_pixels),
        .layer_done(layer_done),

        .photo_data_valid(photo_data_valid),
        .pixel_data_in(pixel_data_in),

        // 포트 이름 일치화
        .weight_wr_en(weight_wr_en),
        .weight_wr_target(weight_wr_target),
        .weight_wr_addr(weight_wr_addr),
        .weight_wr_data(weight_wr_data),

        .out_data(out_data),
        .out_ch_sel(out_ch_sel),
        .output_valid(output_valid)
    );

    //=========================================================================
    // 4. Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    //=========================================================================
    // 5. Test Scenario
    //=========================================================================
    initial begin
        // 초기화
        reset = 1;
        layer_start = 0;
        layer_is_deep = 0;
        layer_out_pixels = 0;
        
        photo_data_valid = 0;
        pixel_data_in = 0;
        
        weight_wr_en = 0;
        weight_wr_target = 0;
        weight_wr_addr = 0;
        weight_wr_data = 0;

        #50;
        reset = 0;
        #20;

        // (1) Feature 가중치(Weight) 쓰기 (target = 0)
        $display("Loading Feature Weights...");
        weight_wr_target = 0; 
        for (i = 0; i < 10; i = i + 1) begin
            weight_wr_addr = i;
            weight_wr_data = 32'h01010101; 
            weight_wr_en = 1;
            #10;
        end
        weight_wr_en = 0;
        #10;

        // (2) Gate 가중치(Weight) 쓰기 (target = 1)
        $display("Loading Gate Weights...");
        weight_wr_target = 1; 
        for (i = 0; i < 10; i = i + 1) begin
            weight_wr_addr = i;
            weight_wr_data = 32'h02020202; 
            weight_wr_en = 1;
            #10;
        end
        weight_wr_en = 0;
        #20;

        // (3) 레이어 연산 시작 신호
        $display("Starting Layer...");
        layer_is_deep = 0;
        layer_out_pixels = 16'd100;
        layer_start = 1;
        #10;
        layer_start = 0;
        #20;

        // (4) 이미지 픽셀 스트리밍 시작
        $display("Streaming Pixel Data...");
        for (i = 0; i < (LINE_LENGTH * 4); i = i + 1) begin
            photo_data_valid = 1;
            pixel_data_in = i[7:0];
            #10;
        end
        photo_data_valid = 0;

        // (5) 종료 대기
        $display("Waiting for layer_done...");
        wait(layer_done == 1'b1);
        #100;

        $display("Simulation Finished Successfully!");
        $finish;
    end

endmodule
