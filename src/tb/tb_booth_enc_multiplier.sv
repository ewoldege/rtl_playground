`timescale 1ns/1ps

module tb_booth_enc_multiplier;

    // =========================================================================
    // 1. Parameters and Configuration
    // =========================================================================
    parameter MULT_W = 16;
    parameter NUM_RANDOM_TESTS = 10000; 
    
    // DELAY PARAMETER: 
    // We assert inputs 1ns AFTER the clock edge to avoid race conditions 
    // in XSIM where data changes exactly at the sampling edge.
    parameter DRIVE_DELAY = 1ns; 

    // =========================================================================
    // 2. Signals
    // =========================================================================
    logic clk;
    logic rst_n;
    logic valid_i;
    logic signed [MULT_W-1:0] multiplier_i;
    logic signed [MULT_W-1:0] multiplicand_i;
    logic product_valid_o;
    logic signed [2*MULT_W-1:0] product_o;

    // Statistics
    int tests_run = 0;
    int errors = 0;

    // =========================================================================
    // 3. DUT Instantiation
    // =========================================================================
    booth_enc_multiplier #(
        .MULT_W(MULT_W)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_i        (valid_i),
        .multiplier_i   (multiplier_i),
        .multiplicand_i (multiplicand_i),
        .product_valid_o(product_valid_o),
        .product_o      (product_o)
    );

    // =========================================================================
    // 4. Clock Generation
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock (Period 10ns)
    end

    // =========================================================================
    // 5. Scoreboard (Queue)
    // =========================================================================
    logic signed [2*MULT_W-1:0] expected_q [$];

    function logic signed [2*MULT_W-1:0] get_expected(input logic signed [MULT_W-1:0] a, input logic signed [MULT_W-1:0] b);
        return a * b;
    endfunction

    // =========================================================================
    // 6. Stimulus Generation (Driver)
    // =========================================================================
    
    // UPDATED TASK: Includes DRIVE_DELAY
    task drive_input(input logic signed [MULT_W-1:0] a, input logic signed [MULT_W-1:0] b);
        @(posedge clk);
        #(DRIVE_DELAY); // Wait 1ns to move off the active clock edge
        
        valid_i <= 1'b1;
        multiplier_i <= a;
        multiplicand_i <= b;
        
        expected_q.push_back(get_expected(a, b));
    endtask

    initial begin
        // --- Initialization ---
        $display("\n=== Starting Booth Multiplier Testbench ===");
        
        // Initialize inputs to 0
        valid_i = 0;
        multiplier_i = 0;
        multiplicand_i = 0;

        // --- Async Reset Sequence ---
        rst_n = 0;
        repeat (5) @(posedge clk);
        #(DRIVE_DELAY); // Sync reset release with other drivers
        rst_n = 1;
        repeat (2) @(posedge clk);

        // --- Directed Tests (Corner Cases) ---
        $display("--- Running Directed Corner Cases ---");
        
        drive_input(0, 0);
        drive_input(100, 0);
        drive_input(0, -50);
        drive_input(1, 10);
        drive_input(10, 1);
        drive_input(-1, 10);
        drive_input(10, -1);
        drive_input(-5, -5);

        // Max Positive / Max Negative boundaries
        drive_input({1'b0, {(MULT_W-1){1'b1}}}, {1'b0, {(MULT_W-1){1'b1}}}); 
        drive_input({1'b1, {(MULT_W-1){1'b0}}}, {1'b1, {(MULT_W-1){1'b0}}}); 
        drive_input({1'b1, {(MULT_W-1){1'b0}}}, 1);                           
        
        // --- Random Tests ---
        $display("--- Running %0d Random Tests ---", NUM_RANDOM_TESTS);
        repeat (NUM_RANDOM_TESTS) begin
            logic signed [MULT_W-1:0] rand_a, rand_b;
            rand_a = $random; 
            rand_b = $random;
            drive_input(rand_a, rand_b);
        end

        // --- Drain Pipeline ---
        @(posedge clk);
        #(DRIVE_DELAY);
        valid_i <= 0;
        
        // Wait until queue is empty
        fork
            begin
                wait(expected_q.size() == 0);
                repeat(5) @(posedge clk); 
            end
            begin
                #100000;
                $error("TIMEOUT: Pipeline did not drain expected transactions.");
            end
        join_any

        // --- Report Results ---
        if (errors == 0) begin
            $display("\n=============================================");
            $display(" TEST PASSED: %0d vectors verified.", tests_run);
            $display("=============================================\n");
        end else begin
            $display("\n=============================================");
            $display(" TEST FAILED: %0d errors found.", errors);
            $display("=============================================\n");
        end

        $finish;
    end

    // =========================================================================
    // 7. Output Monitor (Checker)
    // =========================================================================
    // Note: The monitor usually does NOT need a delay if using standard NBA (<=),
    // but if you see issues here too, you can sample on `negedge clk` or add a delay.
    // For now, standard checking on posedge is retained.
    always @(posedge clk) begin
        if (rst_n && product_valid_o) begin
            logic signed [2*MULT_W-1:0] expected_val;
            
            if (expected_q.size() == 0) begin
                $error("Error: DUT Asserted Valid Output but no expected result in queue!");
                errors++;
            end else begin
                expected_val = expected_q.pop_front();
                tests_run++;

                if (product_o !== expected_val) begin
                    $error("Mismatch at Test %0d!", tests_run);
                    $display("    Expected: %d (0x%h)", expected_val, expected_val);
                    $display("    Got:      %d (0x%h)", product_o, product_o);
                    errors++;
                end
            end
        end
    end

endmodule