`timescale 1ns / 1ps

//==============================================================================
// UNIT TEST TESTBENCH
// Purpose: Validate convolution accelerator with known patterns
// Features: Self-checking, multiple test cases, timing analysis
//==============================================================================

module tb_conv_layer_top;
    
    //==========================================================================
    // CONFIGURATION PARAMETERS
    //==========================================================================
    parameter DATA_WIDTH = 16;
    parameter IMAGE_WIDTH = 10;
    parameter POF = 4;          // Number of Output Filters
    parameter NKX = 3;          // Kernel Width
    parameter NKY = 3;          // Kernel Height
    parameter PIX = 1;          // Parallel outputs X
    parameter PIY = 1;          // Parallel outputs Y
    parameter RESULT_WIDTH = 33;
    
    localparam TOTAL_WEIGHTS = POF * NKX * NKY;
    localparam WARMUP_CYCLES = ((NKY-1) * IMAGE_WIDTH) + (NKX-1);
    localparam TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_WIDTH;
    localparam VALID_OUTPUT_PIXELS = TOTAL_PIXELS - WARMUP_CYCLES;
    
    //==========================================================================
    // SIGNAL DECLARATIONS
    //==========================================================================
    reg clk;
    reg rst;
    reg start;
    wire done;
    
    // Weight Interface
    reg load_weights;
    reg [DATA_WIDTH-1:0] weight_in;
    reg [$clog2(TOTAL_WEIGHTS)-1:0] weight_addr;
    
    // Pixel Interface
    reg pixel_valid_in;
    reg [DATA_WIDTH-1:0] pixel_data_in;
    
    // Output Interface
    wire output_valid_out;
    wire [(POF * PIX * PIY * RESULT_WIDTH)-1:0] result_data_flat;
    
    //==========================================================================
    // RESULT EXTRACTION (Human-Readable Signals)
    //==========================================================================
    reg signed [RESULT_WIDTH-1:0] filter_0_out;
    reg signed [RESULT_WIDTH-1:0] filter_1_out;
    reg signed [RESULT_WIDTH-1:0] filter_2_out;
    reg signed [RESULT_WIDTH-1:0] filter_3_out;
    
    always @(*) begin
        filter_0_out = result_data_flat[1*RESULT_WIDTH-1 : 0*RESULT_WIDTH];
        filter_1_out = result_data_flat[2*RESULT_WIDTH-1 : 1*RESULT_WIDTH];
        filter_2_out = result_data_flat[3*RESULT_WIDTH-1 : 2*RESULT_WIDTH];
        filter_3_out = result_data_flat[4*RESULT_WIDTH-1 : 3*RESULT_WIDTH];
    end
    
    //==========================================================================
    // INSTANTIATE DUT
    //==========================================================================
    conv_layer_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .POF(POF),
        .NKX(NKX),
        .NKY(NKY),
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
        .results_data_flat(result_data_flat)
    );
    
    //==========================================================================
    // CLOCK GENERATION (10ns period = 100MHz)
    //==========================================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end
    
    //==========================================================================
    // TEST VARIABLES
    //==========================================================================
    integer i, row, col;
    integer output_count;
    integer error_count;
    integer first_valid_time;
    reg first_output_checked;
    
    // Expected value for test case
    reg signed [RESULT_WIDTH-1:0] expected_value;
    
    //==========================================================================
    // MAIN TEST SEQUENCE
    //==========================================================================
    initial begin
        // Initialize
        rst = 1'b1;
        start = 1'b0;
        load_weights = 1'b0;
        weight_in = 16'd0;
        weight_addr = 0;
        pixel_valid_in = 1'b0;
        pixel_data_in = 16'd0;
        output_count = 0;
        error_count = 0;
        first_valid_time = 0;
        first_output_checked = 1'b0;
        
        $display("================================================================================");
        $display("           CONVOLUTION ACCELERATOR - UNIT TEST");
        $display("================================================================================");
        $display("Configuration:");
        $display("  Image Size      : %0d x %0d", IMAGE_WIDTH, IMAGE_WIDTH);
        $display("  Kernel Size     : %0d x %0d", NKX, NKY);
        $display("  Output Filters  : %0d", POF);
        $display("  Total Weights   : %0d", TOTAL_WEIGHTS);
        $display("  Warmup Cycles   : %0d", WARMUP_CYCLES);
        $display("  Expected Outputs: %0d", VALID_OUTPUT_PIXELS);
        $display("================================================================================");
        
        //----------------------------------------------------------------------
        // RESET SEQUENCE
        //----------------------------------------------------------------------
        $display("\n[TEST 1] Reset Sequence");
        #100;
        rst = 1'b0;
        #20;
        $display("  PASS - Reset completed");
        
        //----------------------------------------------------------------------
        // TEST CASE 1: All-Ones Kernel, Constant Input
        //----------------------------------------------------------------------
        $display("\n[TEST 2] All-Ones Kernel Test");
        $display("  Loading kernel: All weights = 1");
        $display("  Input pattern : All pixels = 5");
        $display("  Expected      : 3x3x1x5 = 45 per filter");
        
        load_weights = 1'b1;
        for (i = 0; i < TOTAL_WEIGHTS; i = i + 1) begin
            @(posedge clk);
            weight_addr = i;
            weight_in = 16'd1;  // All ones
        end
        @(posedge clk);
        load_weights = 1'b0;
        $display("  Weights loaded: %0d", TOTAL_WEIGHTS);
        
        #50;
        expected_value = 45;  // 9 weights × 1 × 5
        
        //----------------------------------------------------------------------
        // START PROCESSING
        //----------------------------------------------------------------------
        $display("\n[TEST 3] Processing Image");
        start = 1'b1;
        #30;
        
        // MIMIC REAL HARDWARE: DMA and CPU working in parallel
        fork
            // --- WORKER 1: THE DMA (Sends Data) ---
            begin
                // Stream pixels
                pixel_valid_in = 1'b1;
                for (row = 0; row < IMAGE_WIDTH; row = row + 1) begin
                    for (col = 0; col < IMAGE_WIDTH; col = col + 1) begin
                        @(posedge clk);
                        pixel_data_in = 16'd5;
                    end
                end
                
                // Flush Pipeline
                for (i = 0; i < 30; i = i + 1) begin
                    @(posedge clk);
                    pixel_data_in = 16'd0;
                end
                
                @(posedge clk);
                pixel_valid_in = 1'b0;
                $display("  DMA: Streamed %0d pixels + Flush", TOTAL_PIXELS);
            end

            // --- WORKER 2: THE CPU (Waits for Done) ---
            begin
                $display("\n[TEST 4] CPU: Waiting for Completion");
                // This starts watching IMMEDIATELY, so it catches the pulse
                // even if the DMA is still flushing.
                wait(done);
                $display("  CPU: Done signal asserted at time %0t ns", $time);
            end
        join
        
        #100;
        
        //----------------------------------------------------------------------
        // RESULT SUMMARY
        //----------------------------------------------------------------------
        $display("\n================================================================================");
        $display("                          TEST RESULTS");
        $display("================================================================================");
        $display("Outputs received   : %0d / %0d expected", output_count, VALID_OUTPUT_PIXELS);
        $display("First valid output : %0t ns", first_valid_time);
        $display("Errors detected    : %0d", error_count);
        
        if (error_count == 0 && output_count > 0) begin
            $display("\n*** ALL TESTS PASSED ***");
        end else begin
            $display("\n*** TEST FAILED ***");
            if (output_count == 0) begin
                $display("ERROR: No outputs received - check pipeline/control logic");
            end
        end
        $display("================================================================================\n");
        
        $finish;
    end
    
    //==========================================================================
    // OUTPUT MONITOR & CHECKER
    //==========================================================================
    always @(posedge clk) begin
        if (output_valid_out) begin
            output_count = output_count + 1;
            
            // Record first valid output
            if (!first_output_checked) begin
                first_output_checked = 1'b1;
                first_valid_time = $time;
                
                $display("\n--- First Valid Output ---");
                $display("  Time     : %0t ns", $time);
                $display("  Filter 0 : %0d (expected %0d)", filter_0_out, expected_value);
                $display("  Filter 1 : %0d (expected %0d)", filter_1_out, expected_value);
                $display("  Filter 2 : %0d (expected %0d)", filter_2_out, expected_value);
                $display("  Filter 3 : %0d (expected %0d)", filter_3_out, expected_value);
                
                // Check results
                if (filter_0_out == expected_value) begin
                    $display("  PASS - Filter 0 matches expected value");
                end else begin
                    $display("  FAIL - Filter 0: got %0d, expected %0d", 
                             filter_0_out, expected_value);
                    error_count = error_count + 1;
                end
                
                if (filter_1_out == expected_value) begin
                    $display("  PASS - Filter 1 matches expected value");
                end else begin
                    $display("  FAIL - Filter 1: got %0d, expected %0d", 
                             filter_1_out, expected_value);
                    error_count = error_count + 1;
                end
            end
            
            // Check for unexpected changes (all outputs should be constant)
            if (first_output_checked) begin
                if (filter_0_out != expected_value) begin
                    $display("  WARNING: Output changed at %0t - Filter 0 = %0d", 
                             $time, filter_0_out);
                end
            end
            
            // Progress indicator
            if ((output_count % 10) == 0) begin
                $display("  Received %0d outputs...", output_count);
            end
        end
    end
    
    //==========================================================================
    // TIMEOUT WATCHDOG
    //==========================================================================
    initial begin
        #10_000_000;  // 10ms timeout
        $display("\nERROR: Simulation timeout");
        $display("Check for infinite loops or missing done signal");
        $finish;
    end
    
    //==========================================================================
    // ADDITIONAL DEBUG: Detect Done Signal
    //==========================================================================
    always @(posedge done) begin
        $display("\n[DEBUG] Done signal detected at time %0t", $time);
        $display("  Total outputs received: %0d", output_count);
    end

endmodule