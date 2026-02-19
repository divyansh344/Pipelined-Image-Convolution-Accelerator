`timescale 1ns / 1ps

module weight_buffer #(
    parameter DATA_WIDTH = 16,
    parameter POF = 4, // Number of Output Filters (Parallel Output Features)
    parameter NKX = 3, // Kernel Width
    parameter NKY = 3  // Kernel Height
)(
    input wire clk,
    input wire rst,
    
    // --- WRITE INTERFACE (Serial Load) ---
    input wire we,                                  // Write Enable
    input wire [$clog2(POF * NKX * NKY)-1:0] w_addr,  // Address (0 to 35)
    input wire [DATA_WIDTH-1:0] w_data_in,          // The weight value
    
    // --- READ INTERFACE (Parallel Output) ---
    output wire [POF * NKX * NKY*DATA_WIDTH-1:0] weights_flat_out
    );
     
     // Total number of weights = Filters * Kernal_Size
    localparam TOTAL_WEIGHTS = POF * NKX * NKY;
    
    // The Memory (Registers)
    reg [DATA_WIDTH-1:0] weight_mem [0:TOTAL_WEIGHTS-1];
    
    // Integer for loop
    integer i;
    
    // 1. Write Logic
    always @ (posedge clk) begin
        if(rst) begin
            // Optional: clear weights on reset
            for (i = 0; i < TOTAL_WEIGHTS; i = i + 1) begin
                weight_mem[i] <= 0;
            end
        end
        else if(we) begin
            weight_mem[w_addr] <= w_data_in;  
        end  
    end
    
    // 2. Read Logic (Flattening the Array)
    // We must pack the 2D array 'weight_mem' into a single huge bus
    // to match the mac_array interface.
    
    genvar g;
    generate
        for (g = 0; g < TOTAL_WEIGHTS; g = g + 1) begin : PACK_WEIGHTS
            // Assign each chunk of the bus to a register
            assign weights_flat_out[(g+1)*DATA_WIDTH-1 : g*DATA_WIDTH] = weight_mem[g];
        end
    endgenerate
    
endmodule
