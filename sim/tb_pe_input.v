`timescale 1ns / 1ps

module tb_pe_input;

    reg clk;
    reg reset;
    reg in_valid;
    reg mode_int4;

    reg [7:0] line_out0;
    reg [7:0] line_out1;
    reg [7:0] line_out2;

    wire [7:0] pe_pixel_0;
    wire [7:0] pe_pixel_1;
    wire [7:0] pe_pixel_2;
    wire [7:0] pe_pixel_3;
    wire [7:0] pe_pixel_4;
    wire [7:0] pe_pixel_5;
    wire [7:0] pe_pixel_6;
    wire [7:0] pe_pixel_7;
    wire [7:0] pe_pixel_8;
    wire       out_valid;

    pe_input dut (
        .clk(clk),
        .reset(reset),
        .in_valid(in_valid),
        .mode_int4(mode_int4),

        .line_out0(line_out0),
        .line_out1(line_out1),
        .line_out2(line_out2),

        .pe_pixel_0(pe_pixel_0),
        .pe_pixel_1(pe_pixel_1),
        .pe_pixel_2(pe_pixel_2),
        .pe_pixel_3(pe_pixel_3),
        .pe_pixel_4(pe_pixel_4),
        .pe_pixel_5(pe_pixel_5),
        .pe_pixel_6(pe_pixel_6),
        .pe_pixel_7(pe_pixel_7),
        .pe_pixel_8(pe_pixel_8),

        .out_valid(out_valid)
    );

    always #5 clk = ~clk;   // 100MHz clock

    initial begin
        clk = 0;
        reset = 1;
        in_valid = 0;
        mode_int4 = 0;

        line_out0 = 8'd0;
        line_out1 = 8'd0;
        line_out2 = 8'd0;

        #20;
        reset = 0;

        // =========================
        // INT8 mode test
        // =========================
        in_valid = 1;
        mode_int4 = 0;

        @(posedge clk);
        line_out0 = 8'd11;
        line_out1 = 8'd21;
        line_out2 = 8'd31;

        @(posedge clk);
        line_out0 = 8'd12;
        line_out1 = 8'd22;
        line_out2 = 8'd32;

        @(posedge clk);
        line_out0 = 8'd13;
        line_out1 = 8'd23;
        line_out2 = 8'd33;

        @(posedge clk);
        line_out0 = 8'd14;
        line_out1 = 8'd24;
        line_out2 = 8'd34;

        @(posedge clk);
        line_out0 = 8'd15;
        line_out1 = 8'd25;
        line_out2 = 8'd35;

        #20;

        // =========================
        // invalid test
        // =========================
        in_valid = 0;

        @(posedge clk);
        line_out0 = 8'd99;
        line_out1 = 8'd99;
        line_out2 = 8'd99;

        #20;

        // =========================
        // INT4 mode test
        // =========================
        in_valid = 1;
        mode_int4 = 1;

        @(posedge clk);
        line_out0 = 8'hA1;
        line_out1 = 8'hB2;
        line_out2 = 8'hC3;

        @(posedge clk);
        line_out0 = 8'hD4;
        line_out1 = 8'hE5;
        line_out2 = 8'hF6;

        @(posedge clk);
        line_out0 = 8'h17;
        line_out1 = 8'h28;
        line_out2 = 8'h39;

        @(posedge clk);
        line_out0 = 8'h4A;
        line_out1 = 8'h5B;
        line_out2 = 8'h6C;

        #50;

        $stop;
    end

endmodule