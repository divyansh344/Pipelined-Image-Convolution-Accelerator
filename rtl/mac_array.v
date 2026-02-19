`timescale 1ns / 1ps

module mac_array #(
    parameter PIX_WIDTH = 16,
    parameter ACC_WIDTH = 33,
    
    // --- 1. KERNEL PARAMETERS (Passed to PE) ---
    parameter NKX = 3,      // Kernel Width (Nkx)
    parameter NKY = 3,      // Kernel Height (Nky)
    
    // --- 2. PARALLELISM PARAMETERS (The Distributor Dimensions) ---
    parameter POF = 4,      // Parallel Output Filters (Pof)
    parameter PIX = 1,      // Parallel Output Pixels X (Pix)
    parameter PIY = 1       // Parallel Output Pixels Y (Piy)
)(
    input wire clk,
    input wire rst,
    
    // INPUTS
    // Pixels: We need distinct windows for every spatial tile (Pix * Piy).
    // Total Size = (Pix * Piy) * (NKX * NKY * DataWidth)
    input wire [(PIX*PIY) * (NKX*NKY) * PIX_WIDTH - 1 : 0] pixel_data_flat,
    
    // Weights: We need distinct weights for every filter (Pof).
    // Total Size = (Pof) * (NKX * NKY * DataWidth)
    input wire [POF * (NKX*NKY) * PIX_WIDTH - 1 : 0] weight_data_flat,
    
    // OUTPUT
    // Results: One result per PE. Total = Pof * Pix * Piy.
    output wire [(POF*PIX*PIY) * ACC_WIDTH - 1 : 0] results_flat
);

    // Helper Constants
    localparam KERNEL_SIZE = NKX * NKY;
    localparam KERNEL_BITS = KERNEL_SIZE * PIX_WIDTH;

    // Loop Variables
    genvar f, y, x;

    // =========================================================================
    // DISTRIBUTOR LOGIC (3D Grid Generation)
    // We generate a grid of PEs: Pof (Filters) x Piy (Rows) x Pix (Cols)
    // =========================================================================
    generate
        // Loop 1: Iterate over Output Filters (Pof)
        for (f = 0; f < POF; f = f + 1) begin : FILTER_LOOP
            
            // Loop 2: Iterate over Output Rows (Piy)
            for (y = 0; y < PIY; y = y + 1) begin : ROW_LOOP
                
                // Loop 3: Iterate over Output Columns (Pix)
                for (x = 0; x < PIX; x = x + 1) begin : COL_LOOP
                    
                    // --- A. WEIGHT DISTRIBUTION ---
                    // "Broadcast Weights": All spatial tiles (x,y) for Filter 'f' 
                    // share the EXACT same weights.
                    localparam W_BASE = f * KERNEL_BITS;
                    
                    // --- B. PIXEL DISTRIBUTION ---
                    // "Broadcast Pixels": All filters (f) for Spatial Tile 'x,y' 
                    // share the EXACT same pixels.
                    // Calculate index for the spatial tile (y * Width + x)
                    localparam SPATIAL_IDX = (y * PIX) + x;
                    localparam P_BASE = SPATIAL_IDX * KERNEL_BITS;
                    
                    // --- C. RESULT MAPPING ---
                    // Flatten 3D index to 1D output bus
                    // Mapping Strategy: Tile-Major (all tiles for filter 0, then filter 1...).
                    // We use Tile-Major to keep F0 together: Index = (f * Total_Tiles) + Spatial_Idx
                    localparam RES_IDX = (f * (PIX*PIY)) + SPATIAL_IDX;

                    // --- D. INSTANTIATE PE ---
                    processing_element #(
                        .PIX_WIDTH(PIX_WIDTH),
                        .ACC_WIDTH(ACC_WIDTH),
                        .NKX(NKX),
                        .NKY(NKY)
                    ) u_pe (
                        .clk(clk),
                        .rst(rst),
                        
                        // Connect correct Pixel Window (Shared across Filters)
                        .pixels_flat(pixel_data_flat[ P_BASE +: KERNEL_BITS ]),
                        
                        // Connect correct Weights (Shared across Spatial Tiles)
                        .weights_flat(weight_data_flat[ W_BASE +: KERNEL_BITS ]),
                        
                        // Output Result
                        .result(results_flat[ RES_IDX * ACC_WIDTH +: ACC_WIDTH ])
                    );
                    
                end // End COL_LOOP
            end // End ROW_LOOP
        end // End FILTER_LOOP
    endgenerate

endmodule