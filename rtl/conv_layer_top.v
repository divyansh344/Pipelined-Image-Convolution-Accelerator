`timescale 1ns / 1ps

module conv_layer_top #(
    parameter DATA_WIDTH = 16,
    parameter IMAGE_WIDTH = 640,
    parameter POF = 4, // Output Filters
    
   // --- 1. KERNEL DIMENSIONS ---
    parameter NKX = 3,       // Kernel Width (Nkx)
    parameter NKY = 3,       // Kernel Height (Nky)
    
    // --- 2. PARALLELISM DIMENSIONS ---
    parameter PIX = 1,       // Output Pixels computed in parallel X
    parameter PIY = 1        // Output Pixels computed in parallel Y
)(
    input wire clk,
    input wire rst,
    
    // --- CONTROL INTERFACE ---
    input wire start, // Start Processing Image
    output wire done, // Image Processing Complete
    
    // --- WEIGHT LOADING INTERFACE ---
    input wire load_weights, // High = Loading weights, Low = Processing
    input wire [DATA_WIDTH-1:0] weight_in,
    input wire [$clog2(POF * NKX * NKY)-1:0] weight_addr,
    
    // --- PIXEL INPUT STREAM (From DMA) ---
    input wire pixel_valid_in,
    input wire [DATA_WIDTH-1:0] pixel_data_in,
    
    // --- OUTPUT STREAM (To Output Buffer) ---
    output wire output_valid_out,
    output wire [(POF * PIX * PIY * 33) - 1 : 0] results_data_flat
    );
    
    wire input_valid;  // Gated input signal

    // =========================================================================
    // 1. INTERNAL WIRING (Connecting the Blocks)
    // =========================================================================
    
    // Line Buffer -> Conv Reg Array
    wire [NKY*DATA_WIDTH-1:0] lb_column_data;
    
    // Conv Reg Array -> MAC Array
    wire [(PIX*PIY) * (NKX*NKY) * DATA_WIDTH - 1 : 0] window_data_flat;
    
    // Weight Buffer -> MAC Array
    wire [POF * (NKX*NKY) * DATA_WIDTH - 1 : 0] weights_flat_connected;
    
    // =========================================================================
    // 2. INSTANTIATE MODULES
    // =========================================================================

    // A. WEIGHT BUFFER
    weight_buffer #(
        .DATA_WIDTH(DATA_WIDTH), .POF(POF), 
        .NKX(NKX), .NKY(NKY)
    ) u_weight_buf (
        .clk(clk), .rst(rst),
        .we(load_weights),          // Controlled by external load signal
        .w_addr(weight_addr),
        .w_data_in(weight_in),
        .weights_flat_out(weights_flat_connected) // Feeds MACs
    );

    // B. LINE BUFFER
    line_buffer_unit #(
        .PIX_WIDTH(DATA_WIDTH), .IMAGE_WIDTH(IMAGE_WIDTH)
    ) u_line_buf (
        .clk(clk), .rst(rst),
        .valid_in(input_valid), // Only run when not loading weights
        .pixel_in(pixel_data_in),
        .data_col_out(lb_column_data)
    );

    // C. CONV REGISTER ARRAY (The Sliding Window)
    conv_reg_array #(
        .PIX_WIDTH(DATA_WIDTH), .NKX(NKY), .NKY(NKY), .STRIDE(1)
    ) u_shift_regs (
        .clk(clk), .rst(rst),
        .enable(input_valid),        // Shift when new pixels arrive
        .new_pixel_col_flat(lb_column_data),
        .window_data_flat(window_data_flat)
    );

    // D. MAC ARRAY (The Engine)
    mac_array #(
        .PIX_WIDTH(DATA_WIDTH), .ACC_WIDTH(33), // 32+1 bit accumulator
        
        // 1. Kernel Dimensions
        .NKX(NKX), 
        .NKY(NKY), 
        
        // 2. Parallelism Dimensions
        .POF(POF),
        .PIX(PIX),
        .PIY(PIY)
    ) u_mac_engine (
        .clk(clk), .rst(rst),
        .pixel_data_flat(window_data_flat),
        .weight_data_flat(weights_flat_connected),
        .results_flat(results_data_flat)
    );
    
    // =========================================================================
    // 3. CONTROL LOGIC (The "State Machine")
    // =========================================================================
    
    
    reg [31:0] input_pixel_counter;
    reg [31:0] output_pixel_counter;
    
    wire warmup_done;
    
    // Warmup Logic: Don't output valid data until Line Buffer is full (2 Rows + 2 Pixels)
    localparam WARMUP_CYCLES = ((NKY-1) * IMAGE_WIDTH) + (NKX-1);
    localparam TOTAL_PIXELS  = IMAGE_WIDTH * IMAGE_WIDTH;
    localparam EXPECTED_OUTPUTS = TOTAL_PIXELS - WARMUP_CYCLES;
    
    // Accept pixels only up to TOTAL_PIXELS
    assign input_valid = pixel_valid_in && !load_weights && 
                         (input_pixel_counter < TOTAL_PIXELS);
    
    // Input Pixel Counter
    always @(posedge clk) begin
        if (rst)
            input_pixel_counter <= 0;
        else if (input_valid)
            input_pixel_counter <= input_pixel_counter + 1;
    end
    
    assign warmup_done = (input_pixel_counter >= WARMUP_CYCLES);
    
    // Valid Signal Pipeline (To handle latency)
    reg [8:0] valid_pipe;
    
    
    // PIPELINE DELAY FOR VALID SIGNAL
    // We delay the 'valid' signal to match the math latency (reg_array + MAC)
    always @ (posedge clk) begin
        if(rst)
            valid_pipe <= 0;
        else
            // Shift in the new valid bit
            valid_pipe <= {valid_pipe[7:0], (input_valid && warmup_done)}; 
    end
    
    // The final output is valid only after Warmup AND Pipeline Delays
    assign output_valid_out = valid_pipe[7];
    
    // done Logic
    always @ (posedge clk) begin
        if(rst) begin
            output_pixel_counter <= 0;
        end
        else begin
            if (valid_pipe[7] && output_pixel_counter < EXPECTED_OUTPUTS)
                output_pixel_counter <= output_pixel_counter + 1;
        end
    end
    
    assign done = (output_pixel_counter >= EXPECTED_OUTPUTS);
     
endmodule
