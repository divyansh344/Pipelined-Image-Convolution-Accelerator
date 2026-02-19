`timescale 1ns / 1ps

module mac_unit #(
    parameter DATA_WIDTH = 16
)(
    input wire clk,
    input wire rst,
    
    input signed [DATA_WIDTH-1:0] pixel,
    input signed [DATA_WIDTH-1:0] weight,
    input signed [2*DATA_WIDTH:0] accumulator_in,
    
    output reg signed [2*DATA_WIDTH:0] result_out
    );
    
    // I/P Pipeline Registers
    reg signed [DATA_WIDTH-1:0] a_reg, b_reg;
    reg signed [2*DATA_WIDTH:0] c_reg;
    
    // Pipeline Register For Multiplication Result
    reg signed [2*DATA_WIDTH:0] mult_reg;
    
    always @ (posedge clk) begin
        if(rst) begin
            // Reset The Registers
            a_reg <= 0;
            b_reg <= 0;
            c_reg <= 0;
            mult_reg <= 0;
            result_out <= 0;
        end
        else begin
            // Stage 1: Register Inputs
            a_reg <= pixel;
            b_reg <= weight;
            c_reg <= accumulator_in;
            
            // Stage 2: Multiply
            mult_reg <= a_reg * b_reg;
            
            // Stage 3: Accumulate
            result_out <= mult_reg + c_reg;
        
       end
   end     
    
    
    
endmodule
