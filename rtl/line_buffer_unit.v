`timescale 1ns / 1ps

module line_buffer_unit #(
    parameter PIX_WIDTH = 16,
    parameter IMAGE_WIDTH = 640
)(
    input wire clk,
    input wire rst,
    
    input wire valid_in,                 // Is the input pixel valid?
    input wire [PIX_WIDTH-1:0] pixel_in, // The stream coming from DMA/Input
    
    // OUTPUT: 3 Pixels at once (Column)
    // [47:32] = Row 2 (Oldest)
    // [31:16] = Row 1 (Middle)
    // [15:0]  = Row 0 (Newest/Current)
    output wire [3*PIX_WIDTH-1:0] data_col_out
    );
    
    // Internal wires for the RAMs
    wire [PIX_WIDTH-1:0] lb0_out; // Output of Line Buffer 0
    wire [PIX_WIDTH-1:0] lb1_out; // Output of Line Buffer 1
    
    // Single Pointer for Read-Before-Write operations
    // We only need one because we read and write the SAME slot simultaneously.
    reg [$clog2(IMAGE_WIDTH)-1:0] ptr;
    
    // logic to manage pointers
    always @ (posedge clk) begin
        if(rst) begin
           ptr <= 0;
        end
        else if(valid_in) begin
           // Wrap-around logic for circular addressing
            if(ptr == IMAGE_WIDTH -1)
                ptr <= 0;
            else
                ptr <= ptr + 1;  
        end  
    end
    
    // --- INSTANCE 1: Line Buffer 0 (Stores Row -1) ---
    // Takes "pixel_in", stores it, outputs "old pixel" (Row 1)
    simple_dual_port_ram #(
        .WIDTH(PIX_WIDTH), .DEPTH(IMAGE_WIDTH)
    ) lb0 (
        .clk(clk),
        .we(valid_in),
        .addr_r(ptr),   // Read from current position
        .addr_w(ptr),   // Overwrite same position (Read-Before-Write effect)
        .data_in(pixel_in), 
        .data_out(lb0_out) // This is pixels from 1 row ago
    );

    // --- INSTANCE 2: Line Buffer 1 (Stores Row -2) ---
    // Takes "lb0_out" (Row 1), stores it, outputs "older pixel" (Row 2)
    simple_dual_port_ram #(
        .WIDTH(PIX_WIDTH), .DEPTH(IMAGE_WIDTH)
    ) lb1 (
        .clk(clk),
        .we(valid_in),
        .addr_r(ptr),
        .addr_w(ptr),
        .data_in(lb0_out), // Chain mechanism!
        .data_out(lb1_out) // This is pixels from 2 rows ago
    );

   // ============================================================
    // ALIGNMENT
    // ============================================================
    reg [PIX_WIDTH-1:0] r0_delay1, r0_delay2; // Row 0 needs 2 cycle delays
    reg [PIX_WIDTH-1:0] r1_delay1;            // Row 1 needs 1 cycle delay

    always @(posedge clk) begin
        if (valid_in) begin
            // PATH 0: Delay Input by 2 cycles to match RAM1
            r0_delay1 <= pixel_in;
            r0_delay2 <= r0_delay1; 

            // PATH 1: Delay RAM0 by 1 cycle to match RAM1
            r1_delay1 <= lb0_out;  
        end
    end

    // Concatenate the FULLY ALIGNED versions
    // Now all three components have exactly T+2 latency
    assign data_col_out = {lb1_out, r1_delay1, r0_delay2};
endmodule
