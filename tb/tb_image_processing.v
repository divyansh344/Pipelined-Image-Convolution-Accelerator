`timescale 1ns / 1ps

//==============================================================================
// IMAGE PROCESSING TESTBENCH - PRODUCTION VERSION
// Generates OpenCV-compatible Sobel edge detection outputs
// Fixed timing, proper synchronization, comprehensive error checking
//==============================================================================

`define HEADER_SIZE 1078
`define IMG_WIDTH 512
`define IMG_HEIGHT 512
`define IMG_SIZE 262144  // 512 * 512

module tb_image_processing;

    //==========================================================================
    // PARAMETERS
    //==========================================================================
    parameter DATA_WIDTH = 16;
    parameter IMAGE_WIDTH = `IMG_WIDTH;
    parameter NKX = 3;
    parameter NKY = 3;
    parameter POF = 4;
    parameter PIX = 1;
    parameter PIY = 1;
    parameter RESULT_WIDTH = 33;
    
    localparam WARMUP_CYCLES = ((NKY-1) * IMAGE_WIDTH) + (NKX-1);
    localparam TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_WIDTH;
    localparam EXPECTED_OUTPUTS = TOTAL_PIXELS - WARMUP_CYCLES;

    //==========================================================================
    // DUT SIGNALS
    //==========================================================================
    reg clk;
    reg rst;
    reg start;
    wire done;
    
    // Weight loading
    reg load_weights;
    reg [DATA_WIDTH-1:0] weight_in;
    reg [5:0] weight_addr;
    
    // Pixel streaming
    reg pixel_valid_in;
    reg [DATA_WIDTH-1:0] pixel_data_in;
    
    // Output
    wire output_valid_out;
    wire [(POF * PIX * PIY * RESULT_WIDTH) - 1 : 0] results_data_flat;

    //==========================================================================
    // FILE HANDLING
    //==========================================================================
    integer file_in;
    integer file_out_vert;
    integer file_out_horiz;
    integer file_out_combined;
    
    integer byte_in;
    integer i, row, col;
    integer pixels_received;
    integer pixels_written;
    
    // Statistics
    integer min_v, max_v, min_h, max_h;
    integer sum_v, sum_h;

    //==========================================================================
    // INSTANTIATE DUT
    //==========================================================================
    conv_layer_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .NKX(NKX),
        .NKY(NKY),
        .POF(POF),
        .PIX(PIX),
        .PIY(PIY)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .done(done),
        .load_weights(load_weights),
        .weight_in(weight_in),
        .weight_addr(weight_addr),
        .pixel_valid_in(pixel_valid_in),
        .pixel_data_in(pixel_data_in),
        .output_valid_out(output_valid_out),
        .results_data_flat(results_data_flat)
    );

    //==========================================================================
    // CLOCK GENERATION (100MHz)
    //==========================================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //==========================================================================
    // MAIN TEST SEQUENCE
    //==========================================================================
    initial begin
        // Initialize signals
        rst = 1'b1;
        start = 1'b0;
        load_weights = 1'b0;
        weight_in = 16'd0;
        weight_addr = 6'd0;
        pixel_valid_in = 1'b0;
        pixel_data_in = 16'd0;
        pixels_received = 0;
        pixels_written = 0;
        
        // Statistics
        min_v = 32767;
        max_v = -32768;
        min_h = 32767;
        max_h = -32768;
        sum_v = 0;
        sum_h = 0;
        
        $display("================================================================================");
        $display("           SOBEL EDGE DETECTION - IMAGE PROCESSING TEST");
        $display("================================================================================");
        $display("Configuration:");
        $display("  Image Size      : %0d x %0d", IMAGE_WIDTH, IMAGE_WIDTH);
        $display("  Kernel Size     : %0d x %0d", NKX, NKY);
        $display("  Output Filters  : %0d", POF);
        $display("  Expected Outputs: %0d pixels", EXPECTED_OUTPUTS);
        $display("================================================================================");
        
        //----------------------------------------------------------------------
        // STEP 1: OPEN FILES
        //----------------------------------------------------------------------
        $display("\n[STEP 1] Opening files...");
        file_in = $fopen("lena_gray.bmp", "rb");
        if (file_in == 0) begin
            $display("ERROR: Cannot open 'lena_gray.bmp'");
            $display("Please ensure the file exists in the simulation directory.");
            $finish;
        end
        
        file_out_vert = $fopen("output_vertical.bmp", "wb");
        file_out_horiz = $fopen("output_horizontal.bmp", "wb");
        file_out_combined = $fopen("output_combined.bmp", "wb");
        
        if (file_out_vert == 0 || file_out_horiz == 0 || file_out_combined == 0) begin
            $display("ERROR: Cannot create output files");
            $finish;
        end
        
        $display("  Files opened successfully");
        
        //----------------------------------------------------------------------
        // STEP 2: COPY BMP HEADERS
        //----------------------------------------------------------------------
        $display("\n[STEP 2] Copying BMP headers (%0d bytes)...", `HEADER_SIZE);
        for (i = 0; i < `HEADER_SIZE; i = i + 1) begin
            byte_in = $fgetc(file_in);
            if (byte_in == -1) begin
                $display("ERROR: Unexpected EOF in header at byte %0d", i);
                $finish;
            end
            $fwrite(file_out_vert, "%c", byte_in);
            $fwrite(file_out_horiz, "%c", byte_in);
            $fwrite(file_out_combined, "%c", byte_in);
        end
        $display("  Headers copied successfully");
        
        //----------------------------------------------------------------------
        // STEP 3: RESET SEQUENCE
        //----------------------------------------------------------------------
        $display("\n[STEP 3] Applying reset...");
        repeat(10) @(posedge clk);
        rst = 1'b0;
        repeat(2) @(posedge clk);
        $display("  Reset released");
        
        //----------------------------------------------------------------------
        // STEP 4: LOAD SOBEL KERNELS (PROPER SYNCHRONOUS TIMING)
        //----------------------------------------------------------------------
        $display("\n[STEP 4] Loading Sobel kernels...");
        load_weights = 1'b1;
        
        for (i = 0; i < 36; i = i + 1) begin
            @(posedge clk);  // Wait for clock edge FIRST
            #1;  // Small delta delay for signal stability (after clock)
            
            weight_addr = i;
            
            // Filter 0: Sobel Gx (Vertical edges)
            if (i < 9) begin
                case (i % 9)
                    0: weight_in = 16'hFFFF;  // -1
                    1: weight_in = 16'd0;     //  0
                    2: weight_in = 16'd1;     // +1
                    3: weight_in = 16'hFFFE;  // -2
                    4: weight_in = 16'd0;     //  0
                    5: weight_in = 16'd2;     // +2
                    6: weight_in = 16'hFFFF;  // -1
                    7: weight_in = 16'd0;     //  0
                    8: weight_in = 16'd1;     // +1
                    default: weight_in = 16'd0;
                endcase
            end
            // Filter 1: Sobel Gy (Horizontal edges)
            else if (i < 18) begin
                case (i % 9)
                    0: weight_in = 16'hFFFF;  // -1
                    1: weight_in = 16'hFFFE;  // -2
                    2: weight_in = 16'hFFFF;  // -1
                    3: weight_in = 16'd0;     //  0
                    4: weight_in = 16'd0;     //  0
                    5: weight_in = 16'd0;     //  0
                    6: weight_in = 16'd1;     // +1
                    7: weight_in = 16'd2;     // +2
                    8: weight_in = 16'd1;     // +1
                    default: weight_in = 16'd0;
                endcase
            end
            // Filters 2 & 3: Unused
            else begin
                weight_in = 16'd0;
            end
        end
        
        @(posedge clk);
        #1;
        load_weights = 1'b0;
        $display("  Kernels loaded: Sobel Gx, Gy, zeros, zeros");
        
        repeat(5) @(posedge clk);
        
        //----------------------------------------------------------------------
        // STEP 5: START PROCESSING & STREAM PIXELS (PROPER TIMING)
        //----------------------------------------------------------------------
        $display("\n[STEP 5] Streaming pixels...");
        start = 1'b1;
        
        for (row = 0; row < `IMG_HEIGHT; row = row + 1) begin
            for (col = 0; col < `IMG_WIDTH; col = col + 1) begin
                // Read pixel from file
                byte_in = $fgetc(file_in);
                if (byte_in == -1) begin
                    $display("ERROR: Unexpected EOF at pixel [%0d, %0d]", row, col);
                    $finish;
                end
                
                // Wait for clock edge, then set signals
                @(posedge clk);
                #1;  // Delta delay after clock
                pixel_valid_in = 1'b1;
                pixel_data_in = {8'd0, byte_in[7:0]};
                pixels_received = pixels_received + 1;
            end
            
            // Progress indicator
            if ((row % 64) == 0) begin
                $display("  Progress: %0d/%0d rows (%0.1f%%)", 
                         row, `IMG_HEIGHT, (row * 100.0) / `IMG_HEIGHT);
            end
        end
        
        @(posedge clk);
        #1;
        pixel_valid_in = 1'b0;
        $display("  All %0d pixels streamed", TOTAL_PIXELS);
        
        //----------------------------------------------------------------------
        // STEP 6: WAIT FOR COMPLETION
        //----------------------------------------------------------------------
        $display("\n[STEP 6] Waiting for processing completion...");
        wait(done);
        $display("  Done signal received at time %0t ns", $time);
        $display("  Pixels written: %0d / %0d expected", pixels_written, EXPECTED_OUTPUTS);
        
        // Allow pipeline to fully drain
        repeat(20) @(posedge clk);
        
        //----------------------------------------------------------------------
        // STEP 7: PAD OUTPUT FILES
        //----------------------------------------------------------------------
        $display("\n[STEP 7] Padding output files to match input size...");
        while (pixels_written < `IMG_SIZE) begin
            $fwrite(file_out_vert, "%c", 8'd0);
            $fwrite(file_out_horiz, "%c", 8'd0);
            $fwrite(file_out_combined, "%c", 8'd0);
            pixels_written = pixels_written + 1;
        end
        $display("  Padding complete: %0d total pixels", pixels_written);
        
        //----------------------------------------------------------------------
        // STEP 8: STATISTICS
        //----------------------------------------------------------------------
        $display("\n[STEP 8] Processing Statistics:");
        $display("  Vertical Filter (Gx):");
        $display("    Min  : %0d", min_v);
        $display("    Max  : %0d", max_v);
        $display("    Avg  : %0.2f", $itor(sum_v) / $itor(EXPECTED_OUTPUTS));
        
        $display("  Horizontal Filter (Gy):");
        $display("    Min  : %0d", min_h);
        $display("    Max  : %0d", max_h);
        $display("    Avg  : %0.2f", $itor(sum_h) / $itor(EXPECTED_OUTPUTS));
        
        //----------------------------------------------------------------------
        // STEP 9: CLEANUP
        //----------------------------------------------------------------------
        $display("\n[STEP 9] Closing files...");
        $fclose(file_in);
        $fclose(file_out_vert);
        $fclose(file_out_horiz);
        $fclose(file_out_combined);
        
        $display("\n================================================================================");
        $display("                    SIMULATION COMPLETED SUCCESSFULLY");
        $display("================================================================================");
        $display("Output files generated:");
        $display("  - output_vertical.bmp   (Sobel Gx - vertical edges)");
        $display("  - output_horizontal.bmp (Sobel Gy - horizontal edges)");
        $display("  - output_combined.bmp   (Edge magnitude)");
        $display("\nNext steps:");
        $display("  1. Run Python comparison: python image_comparison.py");
        $display("  2. Check verification report for match percentage");
        $display("================================================================================\n");
        
        $finish;
    end

    //==========================================================================
    // OUTPUT CAPTURE & PROCESSING (OpenCV-COMPATIBLE)
    //==========================================================================
    reg signed [RESULT_WIDTH-1:0] raw_vertical;
    reg signed [RESULT_WIDTH-1:0] raw_horizontal;
    reg signed [RESULT_WIDTH-1:0] abs_vertical;
    reg signed [RESULT_WIDTH-1:0] abs_horizontal;
    reg [7:0] pixel_vertical;
    reg [7:0] pixel_horizontal;
    reg [7:0] pixel_combined;
    reg [31:0] magnitude;
    
    always @(posedge clk) begin
        if (output_valid_out) begin
            // Extract raw results from flat bus
            raw_vertical   = results_data_flat[32:0];
            raw_horizontal = results_data_flat[65:33];
            
            // Calculate absolute values (matches OpenCV behavior)
            // OpenCV uses cv2.convertScaleAbs() which takes absolute value
            abs_vertical   = (raw_vertical[32]) ? -raw_vertical : raw_vertical;
            abs_horizontal = (raw_horizontal[32]) ? -raw_horizontal : raw_horizontal;
            
            // Clamp to 8-bit range [0, 255]
            pixel_vertical   = (abs_vertical > 255) ? 8'd255 : abs_vertical[7:0];
            pixel_horizontal = (abs_horizontal > 255) ? 8'd255 : abs_horizontal[7:0];
            
            // Calculate edge magnitude: |Gx| + |Gy|
            // This approximation matches common OpenCV usage
            magnitude = abs_vertical[7:0] + abs_horizontal[7:0];
            pixel_combined = (magnitude > 255) ? 8'd255 : magnitude[7:0];
            
            // Write to output files
            $fwrite(file_out_vert, "%c", pixel_vertical);
            $fwrite(file_out_horiz, "%c", pixel_horizontal);
            $fwrite(file_out_combined, "%c", pixel_combined);
            
            pixels_written = pixels_written + 1;
            
            // Update statistics
            if (abs_vertical < min_v) min_v = abs_vertical;
            if (abs_vertical > max_v) max_v = abs_vertical;
            if (abs_horizontal < min_h) min_h = abs_horizontal;
            if (abs_horizontal > max_h) max_h = abs_horizontal;
            sum_v = sum_v + abs_vertical;
            sum_h = sum_h + abs_horizontal;
        end
    end

    //==========================================================================
    // TIMEOUT WATCHDOG
    //==========================================================================
    initial begin
        #200_000_000;  // 200ms timeout (conservative for 512×512)
        $display("\n");
        $display("================================================================================");
        $display("ERROR: SIMULATION TIMEOUT");
        $display("================================================================================");
        $display("The simulation has exceeded the maximum time limit.");
        $display("Possible causes:");
        $display("  1. Done signal not asserting");
        $display("  2. Pipeline stall");
        $display("  3. Incorrect control logic");
        $display("\nDebug information:");
        $display("  Pixels received: %0d / %0d", pixels_received, TOTAL_PIXELS);
        $display("  Pixels written:  %0d / %0d", pixels_written, EXPECTED_OUTPUTS);
        $display("  Current time:    %0t ns", $time);
        $display("================================================================================\n");
        $finish;
    end

    //==========================================================================
    // DONE SIGNAL MONITOR
    //==========================================================================
    always @(posedge done) begin
        $display("\n[INFO] Done signal asserted at time %0t", $time);
    end

endmodule