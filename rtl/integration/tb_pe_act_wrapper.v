`timescale 1ns / 1ps
//=============================================================================
// File        : tb_pe_act_wrapper.v
// Description : pe_ctrl + bridge + activation_unit 통합 검증용 간단 TB
//
// 실행 방법 (로컬 PC, iverilog 설치 필요: apt-get install iverilog):
//   iverilog -g2012 -o sim.vvp \
//       pe_ctrl.v activation_unit.v reset_bridge.v \
//       mac_to_q88_bridge.v pe_act_wrapper.v tb_pe_act_wrapper.v
//   vvp sim.vvp
//   (GTKWave로 보고 싶으면 $dumpfile/$dumpvars 로 만든 wave.vcd 열기)
//=============================================================================
module tb_pe_act_wrapper;

    reg clk;
    reg reset;
    reg mode_int4;
    reg signed [31:0] mac_result;
    reg valid_d;
    reg pe_enable;
    reg track_sel;

    wire signed [15:0] data_out;
    wire valid_out;

    // 100MHz 가상 클록 (10ns 주기)
    initial clk = 0;
    always #5 clk = ~clk;

    pe_act_wrapper #(
        .DATA_WIDTH(16),
        .FRAC_WIDTH(8)
    ) DUT (
        .clk        (clk),
        .reset      (reset),
        .mode_int4  (mode_int4),
        .mac_result (mac_result),
        .valid_d    (valid_d),
        .pe_enable  (pe_enable),
        .track_sel  (track_sel),
        .data_out   (data_out),
        .valid_out  (valid_out)
    );

    // 편의상 결과를 실수로 환산해서 같이 출력 (Q8.8 -> real)
    real data_out_real;
    always @(*) data_out_real = data_out / 256.0;

    // 입력 인가 후 몇 클럭 뒤에 결과가 나오는지 눈으로 확인하기 위한 로그
    always @(posedge clk) begin
        $display("t=%0t | reset=%b mode_int4=%b track_sel=%b | mac_result=%0d valid_d=%b || data_out=%0d (%f) valid_out=%b",
                   $time, reset, mode_int4, track_sel, mac_result, valid_d, data_out, data_out_real, valid_out);
    end

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_pe_act_wrapper);

        // ---- 초기화 / 리셋 ----
        reset      = 1'b1;
        mode_int4  = 1'b0;   // INT8 모드로 시작
        mac_result = 32'sd0;
        valid_d    = 1'b0;
        pe_enable  = 1'b1;
        track_sel  = 1'b0;   // ReLU
        repeat (3) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);

        // ---- Case 1 : INT8 모드, 정상 범위 양수, ReLU ----
        mode_int4  = 1'b0;
        track_sel  = 1'b0;      // ReLU
        mac_result = 32'sd100000;
        valid_d    = 1'b1;
        @(posedge clk);
        valid_d    = 1'b0;
        repeat (4) @(posedge clk);

        // ---- Case 2 : INT8 모드, saturation 유발 (상한 초과), Sigmoid ----
        mode_int4  = 1'b0;
        track_sel  = 1'b1;      // Sigmoid
        mac_result = 32'sd900000;   // target_max(524287) 초과 -> saturation 확인
        valid_d    = 1'b1;
        @(posedge clk);
        valid_d    = 1'b0;
        repeat (4) @(posedge clk);

        // ---- Case 3 : INT4 모드, 정상 범위 음수, ReLU ----
        mode_int4  = 1'b1;
        track_sel  = 1'b0;      // ReLU
        mac_result = -32'sd1500;
        valid_d    = 1'b1;
        @(posedge clk);
        valid_d    = 1'b0;
        repeat (4) @(posedge clk);

        // ---- Case 4 : INT4 모드, 상한 초과(saturation), Sigmoid ----
        mode_int4  = 1'b1;
        track_sel  = 1'b1;      // Sigmoid
        mac_result = 32'sd3000;     // target_max(2047) 초과 -> saturation 확인
        valid_d    = 1'b1;
        @(posedge clk);
        valid_d    = 1'b0;
        repeat (4) @(posedge clk);

        // ---- Case 5 : enable=0 일 때 valid가 죽는지 확인 ----
        pe_enable  = 1'b0;
        mode_int4  = 1'b0;
        mac_result = 32'sd50000;
        valid_d    = 1'b1;
        @(posedge clk);
        valid_d    = 1'b0;
        pe_enable  = 1'b1;
        repeat (4) @(posedge clk);

        $display("TEST DONE");
        $finish;
    end

endmodule