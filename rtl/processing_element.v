`timescale 1ns / 1ps

module processing_element #(
    parameter PIX_WIDTH = 16,
    parameter ACC_WIDTH = 33,
    parameter NKX = 3, // Kernel Width (e.g., 3)
    parameter NKY = 3  // Kernel Height (e.g., 3)
)(
    input wire clk,
    input wire rst,
    
    // Inputs: Flattened Pixels and Weights
    // Size = Kernel_Width * Kernel_Height * Data_Width
    input wire [NKX*NKY*PIX_WIDTH-1:0] pixels_flat,
    input wire [NKX*NKY*PIX_WIDTH-1:0] weights_flat,
    
    output reg signed [ACC_WIDTH-1:0] result
    );
    
    // Total coefficients in the kernel
    localparam KERNEL_SIZE = NKX*NKY;
    
    // Internal wires for the partial products (MAC outputs)
    wire signed [ACC_WIDTH-1:0] products [0:KERNEL_SIZE-1];
    
    genvar k;
    
    // -------------------------------------------------------------------------
    // 1. Instantiate the MAC Array (The Multipliers)
    // -------------------------------------------------------------------------
    generate
        for (k = 0; k < KERNEL_SIZE; k = k + 1) begin : MACS
            mac_unit #( .DATA_WIDTH(PIX_WIDTH) ) u_mac (
                .clk(clk), 
                .rst(rst),
                // Slice k-th pixel and weight
                .pixel(pixels_flat[ k*PIX_WIDTH +: PIX_WIDTH ]),
                .weight(weights_flat[ k*PIX_WIDTH +: PIX_WIDTH ]),
                .accumulator_in(33'd0), 
                .result_out(products[k])
            );
        end
    endgenerate
    
   // -------------------------------------------------------------------------
    // 2. Pipelined Adder Tree
    // -------------------------------------------------------------------------
    
    // Stage 1 Registers: Partial Sums
    reg signed [ACC_WIDTH-1:0] sum_stage1_0, sum_stage1_1, sum_stage1_2, sum_stage1_3;
    reg signed [ACC_WIDTH-1:0] extra_val;

    always @(posedge clk) begin
        if (rst) begin
            sum_stage1_0 <= 0;
            sum_stage1_1 <= 0;
            sum_stage1_2 <= 0;
            sum_stage1_3 <= 0;
            extra_val    <= 0;
            result       <= 0;
        end
        else begin
            // --- CLOCK CYCLE 1: Add pairs together ---
            // Instead of adding 9 things, we just add 2 or 3 things. Very fast!
            sum_stage1_0 <= products[0] + products[1];
            sum_stage1_1 <= products[2] + products[3];
            sum_stage1_2 <= products[4] + products[5];
            sum_stage1_3 <= products[6] + products[7];
            extra_val    <= products[8]; // Carry the 9th one over

            // --- CLOCK CYCLE 2: Add the partial sums ---
            result <= sum_stage1_0 + sum_stage1_1 + sum_stage1_2 + sum_stage1_3 + extra_val;
        end
    end
      
endmodule
