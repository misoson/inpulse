`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/27 10:24:42
// Design Name: 
// Module Name: tb_line_buffer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_line_buffer();

    parameter DATA_WIDTH = 8;
    parameter LINE_LENGTH = 10;

    reg clk;
    reg reset;
    reg photo_data_valid;
    reg [DATA_WIDTH-1:0] pixel_data_in;

    wire line_data_valid;
    wire [DATA_WIDTH-1:0] line_out0;
    wire [DATA_WIDTH-1:0] line_out1;
    wire [DATA_WIDTH-1:0] line_out2;

    line_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .LINE_LENGTH(LINE_LENGTH)
    ) u_line_buffer (
        .clk(clk),
        .reset(reset),
        .photo_data_valid(photo_data_valid),
        .pixel_data_in(pixel_data_in),
        .line_data_valid(line_data_valid),
        .line_out0(line_out0),
        .line_out1(line_out1),
        .line_out2(line_out2)
    );

    always #5 clk = ~clk;

    integer i;

    initial begin
        clk = 0;
        reset = 1;
        photo_data_valid = 0;
        pixel_data_in = 0;

        #20;
        reset = 0;
        #10;

        photo_data_valid = 1;
        
        for (i = 0; i < LINE_LENGTH * 5; i = i + 1) begin
            pixel_data_in = i; 
            #10;
        end

        photo_data_valid = 0;
        pixel_data_in = 0;
        
        #50;
        
        $finish;
    end

endmodule
