`timescale 1ns / 1ps

module conv_reg_array #(
    parameter PIX_WIDTH = 16, // Width of one pixel (e.g. 16 bits)
    parameter NKX = 3,    // Window Width (e.g. 3)
    parameter NKY = 3,    // Window Height (e.g. 3)
    parameter STRIDE = 1      // Sliding Stride
)(
    input wire clk,
    input wire rst,
    input wire enable,
    
    // INPUT: New column of pixels arriving from Line Buffers/BRAM
    input wire [NKY*PIX_WIDTH-1:0] new_pixel_col_flat,
    
    // OUTPUT: The massive flat wire that goes to mac_array
    output wire [NKY*NKX*PIX_WIDTH-1:0] window_data_flat
    );
    
    // 1. Internal Storage: A 2D array of registers
    // regs[row][col]
    reg [PIX_WIDTH-1:0] shift_regs [0:NKY-1][0:NKX-1];
    
    // 2. Unpack Input (The new column arriving)
    wire [PIX_WIDTH-1:0] new_pixels[0:NKY-1];
    genvar i;
    generate
        for (i = 0; i < NKY; i = i + 1) begin
            assign new_pixels[i] = new_pixel_col_flat[(i+1)*PIX_WIDTH-1 : i*PIX_WIDTH];    
        end
    endgenerate
    
    // 3. Shift Logic
    integer r, c;
    always @ (posedge clk) begin
        if(rst) begin
            // Reset all registers to 0;
            for (r = 0; r < NKY; r = r + 1) begin
                for(c = 0; c < NKX; c = c + 1) begin
                shift_regs[r][c] <= 0;
                end
            end
        end
        else if(enable) begin
            // Shift left
            for (r = 0; r < NKY; r = r + 1) begin
            // A. Move existing pixels: Col 1 becomes Col 0, Col 2 becomes Col 1...
                for (c = 0; c < NKX - 1; c = c + 1) begin
                    shift_regs[r][c] <= shift_regs[r][c+1];
                end
                
                // B. Load new pixel into the last column (The end of the line)
                shift_regs[r][NKX-1] <= new_pixels[r];
            end
        end  
    end
    
    // 4. Flatten the Output for mac_array
    // We map: [Row 0 Col 0], [Row 0 Col 1] ... [Row 1 Col 0] ...
    genvar x, y;
    generate
        for(y = 0; y < NKY; y = y + 1) begin
            for (x = 0; x < NKX; x = x + 1) begin
                // Calculate position in the flat wire
                localparam POS = (y * NKX) + x;
                assign window_data_flat[(POS+1)*PIX_WIDTH-1 : POS*PIX_WIDTH] = shift_regs[y][x];
            end
        end
    endgenerate
 
endmodule
