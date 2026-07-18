`timescale 1ns / 1ps

module tb_npu_top;

    //-------------------------------------------------------------------------
    // 1. Parameter Definitions (탑 모듈 스펙 일치)
    //-------------------------------------------------------------------------
    parameter DATA_WIDTH        = 8;
    parameter LINE_LENGTH       = 32;   // 시뮬레이션 가속을 위해 라인 길이를 32로 축소 (기본값: 1024)
    parameter ACT_DATA_WIDTH    = 16;
    parameter FRAC_WIDTH        = 8;
    parameter CONV_TO_ACT_SHIFT = 0;
    parameter LBUF_RD_LATENCY   = 1;
    parameter SYNC_FIFO_DEPTH   = 4;

    //-------------------------------------------------------------------------
    // 2. Signal Declarations
    //-------------------------------------------------------------------------
    reg clk;
    reg reset;

    // Layer Control
    reg        layer_start;
    reg        layer_is_deep;
    reg [15:0] layer_out_pixels;
    wire       layer_done;

    // Input Pixel Stream
    reg                  photo_data_valid;
    reg [DATA_WIDTH-1:0] pixel_data_in;

    // Feature Weight Buffer Interface
    reg        feat_weight_wr_en;
    reg [3:0]  feat_weight_wr_addr;
    reg [31:0] feat_weight_wr_data;

    // Gate Weight Buffer Interface
    reg        gate_weight_wr_en;
    reg [3:0]  gate_weight_wr_addr;
    reg [31:0] gate_weight_wr_data;

    // Outputs (Four channels, signed Q8.8)
    wire signed [ACT_DATA_WIDTH-1:0] out_ch0;
    wire signed [ACT_DATA_WIDTH-1:0] out_ch1;
    wire signed [ACT_DATA_WIDTH-1:0] out_ch2;
    wire signed [ACT_DATA_WIDTH-1:0] out_ch3;
    wire                             output_valid;

    //-------------------------------------------------------------------------
    // 3. Design Under Test (DUT) Instantiation
    //-------------------------------------------------------------------------
    npu_top #(
        .DATA_WIDTH        (DATA_WIDTH),
        .LINE_LENGTH       (LINE_LENGTH),
        .ACT_DATA_WIDTH    (ACT_DATA_WIDTH),
        .FRAC_WIDTH        (FRAC_WIDTH),
        .CONV_TO_ACT_SHIFT (CONV_TO_ACT_SHIFT),
        .LBUF_RD_LATENCY   (LBUF_RD_LATENCY),
        .SYNC_FIFO_DEPTH   (SYNC_FIFO_DEPTH)
    ) uut (
        .clk                 (clk),
        .reset               (reset),
        .layer_start         (layer_start),
        .layer_is_deep       (layer_is_deep),
        .layer_out_pixels    (layer_out_pixels),
        .layer_done          (layer_done),
        .photo_data_valid    (photo_data_valid),
        .pixel_data_in       (pixel_data_in),
        .feat_weight_wr_en   (feat_weight_wr_en),
        .feat_weight_wr_addr (feat_weight_wr_addr),
        .feat_weight_wr_data (feat_weight_wr_data),
        .gate_weight_wr_en   (gate_weight_wr_en),
        .gate_weight_wr_addr (gate_weight_wr_addr),
        .gate_weight_wr_data (gate_weight_wr_data),
        .out_ch0             (out_ch0),
        .out_ch1             (out_ch1),
        .out_ch2             (out_ch2),
        .out_ch3             (out_ch3),
        .output_valid        (output_valid)
    );

    //-------------------------------------------------------------------------
    // 4. Clock Generation (50MHz, 20ns Cycle)
    //-------------------------------------------------------------------------
    always #10 clk = ~clk;

    //-------------------------------------------------------------------------
    // 5. Test Stimulus Main Process
    //-------------------------------------------------------------------------
    integer idx;
    initial begin
        // 초기 조건 설정
        clk              = 0;
        reset            = 1;
        layer_start      = 0;
        layer_is_deep    = 0;
        layer_out_pixels = 16'd64; // 출력할 가상 픽셀 개수 정의
        photo_data_valid = 0;
        pixel_data_in    = 0;
        
        feat_weight_wr_en   = 0; feat_weight_wr_addr = 0; feat_weight_wr_data = 0;
        gate_weight_wr_en   = 0; gate_weight_wr_addr = 0; gate_weight_wr_data = 0;

        // 시스템 리셋 해제 (100ns 유지)
        #100;
        reset = 0;
        #40;

        // [단계 1] Feature & Gate Weight 버퍼 세팅 (주소별 가상의 가중치 데이터 작성)
        $display("[TB] Writing Configuration to Feature and Gate Weight Buffers...");
        @(posedge clk);
        
        // 간단한 루프를 통해 조원분들의 가중치 버퍼(addr 0~15)에 초기값 입력 기믹 수행
        for(idx=0; idx<8; idx=idx+1) begin
            feat_weight_wr_en   = 1;
            feat_weight_wr_addr = idx;
            feat_weight_wr_data = (idx == 0) ? 32'h01010101 : 32'h00000000; // 가상 가중치 (고정소수점)
            
            gate_weight_wr_en   = 1;
            gate_weight_wr_addr = idx;
            gate_weight_wr_data = (idx == 0) ? 32'h01010101 : 32'h00000000; 
            @(posedge clk);
        end
        feat_weight_wr_en = 0;
        gate_weight_wr_en = 0;
        #40;

        // [단계 2] FSM Controller 구동을 위한 Layer Start 신호 트리거
        $display("[TB] Triggering Layer Start...");
        @(posedge clk);
        layer_start = 1;
        @(posedge clk);
        layer_start = 0;
        @(posedge clk);

        // [단계 3] 가상의 이미지 픽셀 데이터(Stream) 연속 주입
        // 내부 Line Buffer 연산과 PE 연산에 시동이 걸리도록 데이터를 흘려줍니다.
        $display("[TB] Streaming Input Image Pixels...");
        for (idx = 0; idx < 120; idx = idx + 1) begin
            @(posedge clk);
            photo_data_valid = 1;
            pixel_data_in    = idx + 1; // 1, 2, 3... 순으로 픽셀 데이터 변경 주입
        end

        // 스트림 주입 완료 후 인풋 유효 신호 차단
        @(posedge clk);
        photo_data_valid = 0;
        pixel_data_in    = 0;

        // [단계 4] 파형 매칭 및 완료 대기
        // 내부 파이프라인 레이턴시가 지나 출력 유효 신호(output_valid)가 뜰 때까지 관찰
        $display("[TB] Waiting for Gated Convolution Output Valid...");
        
        // 연산이 완료되거나 레이어 종료 플래그(layer_done)가 올 때까지 충분히 시뮬레이션 가동
        wait(layer_done == 1'b1);
        #200;

        $display("[TB] Simulation completed successfully.");
        $finish;
    end

    //-------------------------------------------------------------------------
    // 6. Output Monitoring (Console Log)
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (output_valid) begin
            $display("[OUTPUT LOG] Time=%0t ns | Ch0=%d, Ch1=%d, Ch2=%d, Ch3=%d", 
                      $time, out_ch0, out_ch1, out_ch2, out_ch3);
        end
    end

endmodule
