`timescale 1ns / 1ps

module tb_npu_top;

    //=========================================================================
    // 1. Parameters & Signals
    //=========================================================================
    parameter DATA_WIDTH        = 8;
    parameter LINE_LENGTH       = 1024;
    parameter ACT_DATA_WIDTH    = 16;
    parameter FRAC_WIDTH        = 8;

    // Inputs
    reg clk;
    reg reset;

    // Layer control
    reg        layer_start;
    reg        layer_is_deep;
    reg [15:0] layer_out_pixels;

    // Input pixel stream
    reg                  photo_data_valid;
    reg [DATA_WIDTH-1:0] pixel_data_in;

    // Feature weight buffer
    reg        feat_weight_wr_en;
    reg [3:0]  feat_weight_wr_addr;
    reg [31:0] feat_weight_wr_data;

    // Gate weight buffer
    reg        gate_weight_wr_en;
    reg [3:0]  gate_weight_wr_addr;
    reg [31:0] gate_weight_wr_data;

    // Outputs
    wire                      layer_done;
    wire signed [ACT_DATA_WIDTH-1:0] out_ch0;
    wire signed [ACT_DATA_WIDTH-1:0] out_ch1;
    wire signed [ACT_DATA_WIDTH-1:0] out_ch2;
    wire signed [ACT_DATA_WIDTH-1:0] out_ch3;
    wire                      output_valid;

    integer i;

    //=========================================================================
    // 2. DUT (Device Under Test) Instantiation
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

        .feat_weight_wr_en(feat_weight_wr_en),
        .feat_weight_wr_addr(feat_weight_wr_addr),
        .feat_weight_wr_data(feat_weight_wr_data),

        .gate_weight_wr_en(gate_weight_wr_en),
        .gate_weight_wr_addr(gate_weight_wr_addr),
        .gate_weight_wr_data(gate_weight_wr_data),

        .out_ch0(out_ch0),
        .out_ch1(out_ch1),
        .out_ch2(out_ch2),
        .out_ch3(out_ch3),
        .output_valid(output_valid)
    );

    //=========================================================================
    // 3. Clock Generation
    //=========================================================================
    // 10ns 주기 (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    //=========================================================================
    // 4. Test Scenario
    //=========================================================================
    initial begin
        // 초기값 설정
        reset = 1;
        layer_start = 0;
        layer_is_deep = 0;
        layer_out_pixels = 0;
        
        photo_data_valid = 0;
        pixel_data_in = 0;
        
        feat_weight_wr_en = 0;
        feat_weight_wr_addr = 0;
        feat_weight_wr_data = 0;
        
        gate_weight_wr_en = 0;
        gate_weight_wr_addr = 0;
        gate_weight_wr_data = 0;

        // 리셋 해제 대기
        #50;
        reset = 0;
        #20;

        // (1) 가중치(Weight) 버퍼에 임의의 값 쓰기 (0번 ~ 9번 주소)
        // 실제로는 조원분들이 설계한 데이터 포맷에 맞게 넣어야 합니다.
        $display("Loading Weights...");
        for (i = 0; i < 10; i = i + 1) begin
            // Feature Weight
            feat_weight_wr_addr = i;
            feat_weight_wr_data = 32'h01010101; // 임의의 가중치 값
            feat_weight_wr_en = 1;
            
            // Gate Weight
            gate_weight_wr_addr = i;
            gate_weight_wr_data = 32'h02020202; // 임의의 가중치 값
            gate_weight_wr_en = 1;
            
            #10;
        end
        feat_weight_wr_en = 0;
        gate_weight_wr_en = 0;
        #20;

        // (2) 레이어 연산 시작 신호 (Start)
        $display("Starting Layer...");
        layer_is_deep = 0;
        layer_out_pixels = 16'd100; // 100개의 픽셀 결과를 내보내도록 설정
        layer_start = 1;
        #10;
        layer_start = 0;
        #20;

        // (3) 이미지 픽셀 스트리밍 시작
        // 라인 버퍼가 1024개(LINE_LENGTH)이므로, 최소 3줄(3072개) 이상 들어가야 첫 출력이 나올 수 있습니다.
        $display("Streaming Pixel Data...");
        for (i = 0; i < (LINE_LENGTH * 4); i = i + 1) begin
            photo_data_valid = 1;
            pixel_data_in = i[7:0]; // 0~255 값이 반복해서 들어가게 설정
            #10;
            
            // 데이터가 매 클럭 들어오지 않고 가끔 쉬는 상황을 묘사하고 싶다면 아래 주석 해제
            // photo_data_valid = 0;
            // #10;
        end
        photo_data_valid = 0;

        // (4) 레이어 처리가 끝날 때까지 대기
        $display("Waiting for layer_done...");
        wait(layer_done == 1'b1);
        #100;

        $display("Simulation Finished Successfully!");
        $finish;
    end

endmodule
