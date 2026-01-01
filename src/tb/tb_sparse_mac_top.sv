`timescale 1ns/1ps

import sparse_mac_pkg::*;

module tb_sparse_mac_top;

  // -------------------------------------------------------------------------
  // Parameters
  // -------------------------------------------------------------------------
  localparam int NUM_DECODERS = 2;
  localparam int INPUT_COUNT  = 500; 
  localparam time CLK_PERIOD  = 10ns;
  localparam time INPUT_DELAY = 1ns; 

  logic mac_clk, mac_rst, mac_valid_o;
  logic [NUM_DECODERS-1:0] sram_valid_i, sram_ready_o;
  sram_data_t [NUM_DECODERS-1:0] sram_data_i;
  logic [ACCUM_W-1:0] mac_data_o;

  // Queues and Golden Model Maps
  typedef struct { int skip; int value; } test_vector_t;
  test_vector_t queue_ch0[$], queue_ch1[$];
  int golden_map_ch0[int], golden_map_ch1[int];

  // -------------------------------------------------------------------------
  // DUT
  // -------------------------------------------------------------------------
  sparse_mac_top #(.NUM_DECODERS(NUM_DECODERS)) dut (.*);

  initial begin
    mac_clk = 0;
    forever #(CLK_PERIOD/2) mac_clk = ~mac_clk;
  end

  // -------------------------------------------------------------------------
  // Improved Data Generation
  // -------------------------------------------------------------------------
  initial begin
    longint expected_result;
    integer seed_0 = 123;
    integer seed_1 = 456;

    sram_valid_i = '0;
    sram_data_i  = '0;

    // Generate correlated data to ensure the result is NOT zero
    generate_correlated_data(seed_0, seed_1);

    expected_result = calculate_expected_dot_product();
    $display("[%0t] Golden Model Expected Result: %0d", $time, expected_result);

    // Reset
    mac_rst = 0;
    repeat(5) @(posedge mac_clk);
    #(INPUT_DELAY); 
    mac_rst = 1;
    repeat(2) @(posedge mac_clk);

    fork
      drive_stream(0, queue_ch0);
      drive_stream(1, queue_ch1);
      monitor_output(expected_result);
    join

    $finish;
  end

  // This function generates indices for both streams simultaneously 
  // to guarantee overlap (collisions)
  function void generate_correlated_data(int s0, int s1);
    int idx_a = -1;
    int idx_b = -1;
    int skip, val;

    for (int i = 0; i < INPUT_COUNT; i++) begin
      // Stream 0 Generation
      skip = $unsigned($random(s0)) % 3; // Keep skips small (0, 1, or 2)
      val  = ($unsigned($random(s0)) % 10) + 1;
      idx_a = idx_a + skip + 1;
      golden_map_ch0[idx_a] = val;
      queue_ch0.push_back('{skip: skip, value: val});

      // Stream 1 Generation
      // Occasionally "force" Stream 1 to match Stream 0's index
      if (($unsigned($random(s1)) % 10) > 7) begin 
        // Force a collision: Skip exactly to where Stream A is
        skip = (idx_a > idx_b) ? (idx_a - idx_b - 1) : 0;
      end else begin
        skip = $unsigned($random(s1)) % 3;
      end
      
      val  = ($unsigned($random(s1)) % 10) + 1;
      idx_b = idx_b + skip + 1;
      golden_map_ch1[idx_b] = val;
      queue_ch1.push_back('{skip: skip, value: val});
    end
  endfunction

  function longint calculate_expected_dot_product();
    longint total = 0;
    foreach (golden_map_ch0[idx]) begin
      if (golden_map_ch1.exists(idx)) begin
        total += (longint'(golden_map_ch0[idx]) * longint'(golden_map_ch1[idx]));
      end
    end
    return total;
  endfunction

  // -------------------------------------------------------------------------
  // Driving and Monitoring Tasks (Same as before but integrated)
  // -------------------------------------------------------------------------
  task automatic drive_stream(input int ch, ref test_vector_t q[$]);
    test_vector_t item;
    while(q.size() > 0) begin
      item = q.pop_front();
      @(posedge mac_clk); #(INPUT_DELAY);
      sram_valid_i[ch] <= 1'b1;
      sram_data_i[ch]  <= '{done: 1'b0, value: item.value, skip: item.skip};
      
      do begin
        @(negedge mac_clk);
      end while (!sram_ready_o[ch]);
    end

    // Send Done
    @(posedge mac_clk); #(INPUT_DELAY);
    sram_data_i[ch].done <= 1'b1;
    sram_data_i[ch].value <= '0;
    sram_data_i[ch].skip  <= '0;
    do begin @(negedge mac_clk); end while (!sram_ready_o[ch]);
    
    @(posedge mac_clk); #(INPUT_DELAY);
    sram_valid_i[ch] <= 1'b0;
  endtask

  task automatic monitor_output(input longint expected);
    wait(mac_valid_o);
    $display("---------------------------------------------------");
    $display("FINAL MAC OUTPUT: %0d | EXPECTED: %0d", mac_data_o, expected);
    if (mac_data_o == expected) $display("RESULT: PASS");
    else                        $display("RESULT: FAIL");
    $display("---------------------------------------------------");
  endtask

endmodule