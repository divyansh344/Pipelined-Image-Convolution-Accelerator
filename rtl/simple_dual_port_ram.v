`timescale 1ns / 1ps

module simple_dual_port_ram #(
    parameter WIDTH = 16,
    parameter DEPTH = 640 // eg. Image width  
)(
    input wire clk,
    input wire we,
    
    input wire [$clog2(DEPTH)-1:0] addr_r,
    input wire [$clog2(DEPTH)-1:0] addr_w,
    
    input wire [WIDTH-1:0] data_in,
    output reg [WIDTH-1:0] data_out
    );
    
    reg [WIDTH-1:0] ram [0:DEPTH-1];
    
    always @ (posedge clk) begin
        // write port
        if(we)
            ram[addr_w] <= data_in;
        
        // read port   
        data_out <= ram[addr_r];     
    end
       
endmodule
