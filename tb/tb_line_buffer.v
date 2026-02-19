`timescale 1ns / 1ps

module tb_line_buffer;

    // Parameters
    // We use a small width (4) so we can see the "Row Wrapping" quickly.
    // In the real design, this is 640.
    parameter PIX_WIDTH = 16;
    parameter IMAGE_WIDTH = 4; 

    // Inputs
    reg clk;
    reg rst;
    reg valid_in;
    reg [PIX_WIDTH-1:0] pixel_in;

    // Outputs
    wire [3*PIX_WIDTH-1:0] data_col_out;
    
    // Internal wires to unpack the output for easier viewing in waveform
    wire [15:0] row0_new;
    wire [15:0] row1_delayed;
    wire [15:0] row2_old;

    // Instantiate the Unit Under Test (UUT)
    line_buffer_unit #(
        .PIX_WIDTH(PIX_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH)
    ) uut (
        .clk(clk), 
        .rst(rst), 
        .valid_in(valid_in), 
        .pixel_in(pixel_in), 
        .data_col_out(data_col_out)
    );

    // Unpack the output so you can see separate rows in the waveform
    assign {row2_old, row1_delayed, row0_new} = data_col_out;

    // Clock generation (10ns period)
    always #5 clk = ~clk;

    initial begin
        // 1. Initialize Inputs
        clk = 0;
        rst = 1;
        valid_in = 0;
        pixel_in = 0;

        // 2. Reset the system
        #20;
        rst = 0;
        
        // 3. Start sending pixels
        // We will send 16 pixels (Enough for 4 full rows of width 4)
        valid_in = 1;
        
        // ROW 0 (Pixels 1, 2, 3, 4)
        pixel_in = 16'd1; #10;
        pixel_in = 16'd2; #10;
        pixel_in = 16'd3; #10;
        pixel_in = 16'd4; #10;
        
        // ROW 1 (Pixels 11, 12, 13, 14) -> "11" helps distinguish row 1
        pixel_in = 16'd11; #10;
        pixel_in = 16'd12; #10;
        pixel_in = 16'd13; #10;
        pixel_in = 16'd14; #10;
        
        // ROW 2 (Pixels 21, 22, 23, 24)
        pixel_in = 16'd21; #10;
        pixel_in = 16'd22; #10;
        pixel_in = 16'd23; #10;
        pixel_in = 16'd24; #10;

        // ROW 3 (Pixels 31, 32, 33, 34)
        pixel_in = 16'd31; #10;
        pixel_in = 16'd32; #10;
        pixel_in = 16'd33; #10;
        pixel_in = 16'd34; #10;

        // End simulation
        valid_in = 0;
        #50;
        $finish;
    end
      
endmodule