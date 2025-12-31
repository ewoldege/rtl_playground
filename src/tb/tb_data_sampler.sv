`timescale 1ns/1ps

module tb_data_sampler;

    // Parameters
    parameter int DATA_W = 64;
    parameter real FAST_PERIOD = 10.0;    // 100 MHz
    parameter real SLOW_PERIOD = 33.333;  // ~30 MHz

    // Signals
    logic fast_clk = 0;
    logic slow_clk = 0;
    logic rst_n; 

    logic [DATA_W-1:0] data_i;
    logic              valid_i;
    logic [DATA_W-1:0] data_o;
    logic              valid_o;

    //---------------------------------------------------------
    // Clock Generation
    //---------------------------------------------------------
    always #(FAST_PERIOD/2) fast_clk = ~fast_clk;
    
    initial begin
        #1.7ns; // Asynchronous phase offset
        forever #(SLOW_PERIOD/2) slow_clk = ~slow_clk;
    end

    //---------------------------------------------------------
    // DUT Instance
    //---------------------------------------------------------
    data_sampler #(.DATA_W(DATA_W)) dut (.*, .rst(rst_n));

    //---------------------------------------------------------
    // Stimulus (Fast Domain - Fire and Forget)
    //---------------------------------------------------------
    initial begin
        rst_n   = 1'b0;
        valid_i = 1'b0;
        data_i  = '0;

        #(FAST_PERIOD * 10);
        rst_n = 1'b1;
        repeat(5) @(posedge fast_clk);

        // Sending a burst of data pulses
        // Some will be missed by the slow clock due to the frequency ratio
        for (int i = 1; i <= 20; i++) begin
            @(posedge fast_clk);
            data_i  = i; // Simple counter to track which samples are caught
            valid_i = 1'b1;
            
            @(posedge fast_clk);
            valid_i = 1'b0;
            data_i  = 'x; // Stress the hold time/sampling window
            
            // Random gap between pulses
            repeat($urandom_range(1, 5)) @(posedge fast_clk);
        end

        #(SLOW_PERIOD * 10);
        $display("Testbench complete.");
        $finish;
    end

    //---------------------------------------------------------
    // Monitor & Data Loss Analysis
    //---------------------------------------------------------
    int captured_count = 0;

    always @(posedge slow_clk) begin
        if (valid_o) begin
            captured_count++;
            $display("[%0t] Captured Sample #%0d: Value = 0x%h", 
                     $time, captured_count, data_o);
        end
    end

endmodule