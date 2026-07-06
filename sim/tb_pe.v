`timescale 1ns / 1ps

module tb_pe;

    parameter DATA_WIDTH = 8;

    reg clk;
    reg reset;
    reg mode_int4;
    reg in_valid;

    reg [DATA_WIDTH-1:0] line_out0;
    reg [DATA_WIDTH-1:0] line_out1;
    reg [DATA_WIDTH-1:0] line_out2;

    reg signed [DATA_WIDTH-1:0] weight_0;
    reg signed [DATA_WIDTH-1:0] weight_1;
    reg signed [DATA_WIDTH-1:0] weight_2;
    reg signed [DATA_WIDTH-1:0] weight_3;
    reg signed [DATA_WIDTH-1:0] weight_4;
    reg signed [DATA_WIDTH-1:0] weight_5;
    reg signed [DATA_WIDTH-1:0] weight_6;
    reg signed [DATA_WIDTH-1:0] weight_7;
    reg signed [DATA_WIDTH-1:0] weight_8;

    reg signed [31:0] bias;

    wire signed [31:0] conv_out;
    wire valid_out;

    pe #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .reset(reset),
        .mode_int4(mode_int4),
        .in_valid(in_valid),

        .line_out0(line_out0),
        .line_out1(line_out1),
        .line_out2(line_out2),

        .weight_0(weight_0),
        .weight_1(weight_1),
        .weight_2(weight_2),
        .weight_3(weight_3),
        .weight_4(weight_4),
        .weight_5(weight_5),
        .weight_6(weight_6),
        .weight_7(weight_7),
        .weight_8(weight_8),

        .bias(bias),

        .conv_out(conv_out),
        .valid_out(valid_out)
    );

    // 100MHz clock
    always #5 clk = ~clk;

    task send_column;
        input [7:0] p0;
        input [7:0] p1;
        input [7:0] p2;
        begin
            @(negedge clk);
            in_valid = 1'b1;
            line_out0 = p0;
            line_out1 = p1;
            line_out2 = p2;
        end
    endtask

    task stop_input;
        begin
            @(negedge clk);
            in_valid = 1'b0;
            line_out0 = 0;
            line_out1 = 0;
            line_out2 = 0;
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        mode_int4 = 0;
        in_valid = 0;

        line_out0 = 0;
        line_out1 = 0;
        line_out2 = 0;

        // weight 전부 1로 설정
        weight_0 = 8'sd1;
        weight_1 = 8'sd1;
        weight_2 = 8'sd1;
        weight_3 = 8'sd1;
        weight_4 = 8'sd1;
        weight_5 = 8'sd1;
        weight_6 = 8'sd1;
        weight_7 = 8'sd1;
        weight_8 = 8'sd1;

        bias = 32'sd0;

        #20;
        reset = 0;

        // =====================================================
        // TEST 1: INT8 mode
        // weight가 전부 1이므로 3x3 window의 단순 합이 출력됨
        // =====================================================
        mode_int4 = 0;

        send_column(8'd1,  8'd10, 8'd20);
        send_column(8'd2,  8'd11, 8'd21);
        send_column(8'd3,  8'd12, 8'd22);
        send_column(8'd4,  8'd13, 8'd23);
        send_column(8'd5,  8'd14, 8'd24);
        send_column(8'd6,  8'd15, 8'd25);

        stop_input();

        repeat(6) @(posedge clk);

        // =====================================================
        // TEST 2: INT4 mode
        // 하위 4비트만 사용되는지 확인
        // 예: 8'h1F -> 4'hF = 15
        // =====================================================
        reset = 1;
        #20;
        reset = 0;

        mode_int4 = 1;

        send_column(8'h11, 8'h12, 8'h13); // 1,2,3
        send_column(8'h14, 8'h15, 8'h16); // 4,5,6
        send_column(8'h17, 8'h18, 8'h19); // 7,8,9
        send_column(8'h1A, 8'h1B, 8'h1C); // 10,11,12
        send_column(8'h1D, 8'h1E, 8'h1F); // 13,14,15

        stop_input();

        repeat(10) @(posedge clk);

        $display("TB finished.");
        $finish;
    end

    always @(posedge clk) begin
        if (valid_out) begin
            $display("[%0t] mode_int4=%b, conv_out=%0d", 
                     $time, mode_int4, conv_out);
        end
    end

endmodule