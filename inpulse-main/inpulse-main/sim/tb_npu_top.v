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

    // [수정 반영] Shared Weight Buffer Interface
    reg        weight_wr_en;
    reg        weight_wr_target;
    reg [3:0]  weight_wr_addr;
    reg [31:0] weight_wr_data;

    // [수정 반영] Time-multiplexed Serialized Outputs
    wire signed [ACT_DATA_WIDTH-1:0] out_data;
    wire [1:0]                       out_ch_sel;
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
        .clk              (clk),
        .reset            (reset),
        .layer_start      (layer_start),
        .layer_is_deep    (layer_is_deep),
        .layer_out_pixels (layer_out_pixels),
        .layer_done       (layer_done),
        .photo_data_valid (photo_data_valid),
        .pixel_data_in    (pixel_data_in),
        .weight_wr_en     (weight_wr_en),
        .weight_wr_target (weight_wr_target),
        .weight_wr_addr   (weight_wr_addr),
        .weight_wr_data   (weight_wr_data),
        .out_data         (out_data),
        .out_ch_sel       (out_ch_sel),
        .output_valid     (output_valid)
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
        layer_out_pixels = 16'd64; // 가상 레이어 연산 픽셀 타겟 수
        photo_data_valid = 0;
        pixel_data_in    = 0;
        
        weight_wr_en     = 0;
        weight_wr_target = 0;
        weight_wr_addr   = 0;
        weight_wr_data   = 0;

        // 동기식 리셋 해제 (100ns 유지)
        #100;
        reset = 0;
        #40;

        // [단계 1] 공용 버스를 이용한 Feature 및 Gate Weight 버퍼 순차 작성
        $display("[TB] Writing to Feature Weight Buffer (Target = 0)...");
        for(idx = 0; idx < 8; idx = idx + 1) begin
            @(posedge clk);
            weight_wr_en     = 1;
            weight_wr_target = 0; // Feature 선택
            weight_wr_addr   = idx;
            weight_wr_data   = (idx == 0) ? 32'h01010101 : 32'h00000000; // 예시용 단위 행렬 가중치 세팅
        end
        
        @(posedge clk);
        $display("[TB] Writing to Gate Weight Buffer (Target = 1)...");
        for(idx = 0; idx < 8; idx = idx + 1) begin
            @(posedge clk);
            weight_wr_en     = 1;
            weight_wr_target = 1; // Gate 선택
            weight_wr_addr   = idx;
            weight_wr_data   = (idx == 0) ? 32'h01010101 : 32'h00000000; 
        end
        
        @(posedge clk);
        weight_wr_en = 0;
        #40;

        // [단계 2] 레이어 시작 신호(Layer Start) 발생
        $display("[TB] Triggering Layer Start...");
        @(posedge clk);
        layer_start = 1;
        @(posedge clk);
        layer_start = 0;
        @(posedge clk);

        // [단계 3] 이미지 입력 픽셀 스트림 주입
        $display("[TB] Streaming Input Image Pixels into Shared Line Buffer...");
        for (idx = 0; idx < 120; idx = idx + 1) begin
            @(posedge clk);
            photo_data_valid = 1;
            pixel_data_in    = idx + 1; // 1, 2, 3... 가산 데이터 스트림 입력
        end

        // 스트림 주입 완료 후 비활성화
        @(posedge clk);
        photo_data_valid = 0;
        pixel_data_in    = 0;

        // [단계 4] 레이어 종료 신호 대기 및 시뮬레이션 종료
        $display("[TB] Waiting for layer_done signal from FSM Controller...");
        wait(layer_done == 1'b1);
        #200;

        $display("[TB] All tests completed successfully.");
        $finish;
    end

    //-------------------------------------------------------------------------
    // 6. Time-multiplexed Output Monitoring (Console Log)
    //-------------------------------------------------------------------------
    // 4-cycle 시분할 출력을 낚아채서 콘솔에 사람이 읽기 편한 로그로 출력합니다.
    always @(posedge clk) begin
        if (output_valid) begin
            $display("[OUTPUT LOG] Time=%0t ns | Ch Sel=%d | Serial Data=%d", 
                      $time, out_ch_sel, out_data);
        end
    end

endmodule
