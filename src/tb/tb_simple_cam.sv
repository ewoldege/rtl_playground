`timescale 1ns/1ps

module tb_simple_cam;

  localparam int CAM_W       = 32;
  localparam int CAM_DEPTH   = 64;
  localparam int CAM_DEPTH_W = $clog2(CAM_DEPTH);

  logic clk;
  logic rst_n;

  logic                   wren;
  logic [CAM_W-1:0]       wdata;
  logic [CAM_DEPTH_W-1:0] waddr;

  logic                   lookup_en;
  logic [CAM_W-1:0]       lookup_val;
  logic [CAM_DEPTH_W-1:0] lookup_winner;
  logic                   lookup_resp_valid;
  logic                   lookup_hit;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  simple_cam #(
    .CAM_W      (CAM_W),
    .CAM_DEPTH  (CAM_DEPTH),
    .CAM_DEPTH_W(CAM_DEPTH_W)
  ) dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .wren             (wren),
    .wdata            (wdata),
    .waddr            (waddr),
    .lookup_en        (lookup_en),
    .lookup_val       (lookup_val),
    .lookup_winner    (lookup_winner),
    .lookup_resp_valid(lookup_resp_valid),
    .lookup_hit       (lookup_hit)
  );

  // --------------------------------------------------------------------------
  // Clock
  // --------------------------------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // --------------------------------------------------------------------------
  // Reference model
  // --------------------------------------------------------------------------
  logic [CAM_W-1:0] model_mem   [0:CAM_DEPTH-1];
  bit               model_valid [0:CAM_DEPTH-1];

  logic                   exp_resp_valid_q;
  logic                   exp_hit_q;
  logic [CAM_DEPTH_W-1:0] exp_winner_q;

  int errors;

  // exact-match lookup model
  // lowest index wins on multiple hits
  task automatic model_lookup(
    input  logic [CAM_W-1:0]       key,
    output logic                   hit,
    output logic [CAM_DEPTH_W-1:0] winner
  );
    int i;
    begin
      hit    = 1'b0;
      winner = '0;

      for (i = 0; i < CAM_DEPTH; i++) begin
        if (!hit && model_valid[i] && (model_mem[i] == key)) begin
          hit    = 1'b1;
          winner = i[CAM_DEPTH_W-1:0];
        end
      end
    end
  endtask

  task automatic check_outputs;
    begin
      if (lookup_resp_valid !== exp_resp_valid_q) begin
        $display("[%0t] ERROR: lookup_resp_valid mismatch. exp=%0b got=%0b",
                 $time, exp_resp_valid_q, lookup_resp_valid);
        errors++;
      end

      if (exp_resp_valid_q) begin
        if (lookup_hit !== exp_hit_q) begin
          $display("[%0t] ERROR: lookup_hit mismatch. exp=%0b got=%0b",
                   $time, exp_hit_q, lookup_hit);
          errors++;
        end

        if (exp_hit_q && (lookup_winner !== exp_winner_q)) begin
          $display("[%0t] ERROR: lookup_winner mismatch. exp=%0d got=%0d",
                   $time, exp_winner_q, lookup_winner);
          errors++;
        end
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // Cycle-step task
  //
  // Semantics:
  //   - Inputs currently on the DUT are sampled at the next posedge
  //   - DUT response at that posedge is checked against exp_*_q
  //   - Current-cycle write is then applied to the reference model
  //   - New inputs are driven for the following cycle
  //   - Expected response for the following cycle is queued with <=
  //
  // This assumes same-cycle write+lookup uses PRE-WRITE contents for lookup.
  // --------------------------------------------------------------------------
  task automatic step(
    input logic                   next_wren,
    input logic [CAM_DEPTH_W-1:0] next_waddr,
    input logic [CAM_W-1:0]       next_wdata,
    input logic                   next_lookup_en,
    input logic [CAM_W-1:0]       next_lookup_val
  );
    logic                   next_hit;
    logic [CAM_DEPTH_W-1:0] next_winner;
    begin
      // Advance one clock: DUT consumes current inputs here
      @(posedge clk);
      #1;

      if (rst_n) begin
        // Check DUT response for the inputs that were applied during the prior cycle
        check_outputs();

        // Update reference model with the write that happened on this edge
        if (wren) begin
          model_mem[waddr]   = wdata;
          model_valid[waddr] = 1'b1;
        end
      end

      // Drive inputs for the NEXT cycle
      wren       <= next_wren;
      waddr      <= next_waddr;
      wdata      <= next_wdata;
      lookup_en  <= next_lookup_en;
      lookup_val <= next_lookup_val;

      // Compute expected response for the NEXT cycle
      if (next_lookup_en) begin
        model_lookup(next_lookup_val, next_hit, next_winner);
      end
      else begin
        next_hit    = 1'b0;
        next_winner = '0;
      end

      // Queue expected outputs (nonblocking as requested)
      exp_resp_valid_q <= next_lookup_en;
      exp_hit_q        <= next_hit;
      exp_winner_q     <= next_winner;
    end
  endtask

  task automatic idle_cycle;
    begin
      step(1'b0, '0, '0, 1'b0, '0);
    end
  endtask

  task automatic write_entry(
    input logic [CAM_DEPTH_W-1:0] addr,
    input logic [CAM_W-1:0]       data
  );
    begin
      step(1'b1, addr, data, 1'b0, '0);
    end
  endtask

  task automatic lookup_only(
    input logic [CAM_W-1:0] key
  );
    begin
      step(1'b0, '0, '0, 1'b1, key);
    end
  endtask

  function automatic bit any_valid_entries();
    int i;
    begin
      any_valid_entries = 1'b0;
      for (i = 0; i < CAM_DEPTH; i++) begin
        if (model_valid[i]) begin
          any_valid_entries = 1'b1;
        end
      end
    end
  endfunction

  task automatic get_random_existing_value(
    output logic [CAM_W-1:0] val
  );
    int idx;
    int tries;
    begin
      val = $urandom;
      for (tries = 0; tries < 50; tries++) begin
        idx = $urandom_range(0, CAM_DEPTH-1);
        if (model_valid[idx]) begin
          val = model_mem[idx];
          return;
        end
      end
    end
  endtask

  task automatic random_cycle;
    logic                   wren_i;
    logic [CAM_DEPTH_W-1:0] waddr_i;
    logic [CAM_W-1:0]       wdata_i;
    logic                   lookup_en_i;
    logic [CAM_W-1:0]       lookup_val_i;
    begin
      wren_i      = $urandom_range(0,1);
      lookup_en_i = $urandom_range(0,1);
      waddr_i     = $urandom_range(0, CAM_DEPTH-1);

      // Sometimes create duplicates intentionally
      if (any_valid_entries() && ($urandom_range(0,99) < 35)) begin
        get_random_existing_value(wdata_i);
      end
      else begin
        wdata_i = $urandom;
      end

      // Bias lookups toward hits
      if (any_valid_entries() && ($urandom_range(0,99) < 65)) begin
        get_random_existing_value(lookup_val_i);
      end
      else begin
        lookup_val_i = $urandom;
      end

      step(wren_i, waddr_i, wdata_i, lookup_en_i, lookup_val_i);
    end
  endtask

  task automatic apply_reset;
    int i;
    begin
      wren       = 1'b0;
      waddr      = '0;
      wdata      = '0;
      lookup_en  = 1'b0;
      lookup_val = '0;
      rst_n      = 1'b0;

      exp_resp_valid_q = 1'b0;
      exp_hit_q        = 1'b0;
      exp_winner_q     = '0;
      errors           = 0;

      for (i = 0; i < CAM_DEPTH; i++) begin
        model_mem[i]   = '0;
        model_valid[i] = 1'b0;
      end

      repeat (3) @(posedge clk);
      rst_n = 1'b1;
    end
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_simple_cam);
    apply_reset();

    // Prime one idle cycle after reset
    idle_cycle();

    // 1) Empty CAM miss
    // response next cycle: resp_valid=1, hit=0
    lookup_only(32'hDEAD_BEEF);
    idle_cycle();

    // 2) Single write / single hit
    write_entry(6'd5, 32'h1111_2222);
    lookup_only(32'h1111_2222);
    idle_cycle();

    // 3) Another miss
    lookup_only(32'h3333_4444);
    idle_cycle();

    // 4) Multiple-hit test: lowest index wins
    write_entry(6'd10, 32'hCAFE_BABE);
    write_entry(6'd2,  32'hCAFE_BABE);
    lookup_only(32'hCAFE_BABE);
    idle_cycle();

    // 5) Overwrite one duplicate entry
    write_entry(6'd2, 32'h1234_5678);

    lookup_only(32'hCAFE_BABE); // should now hit addr 10
    idle_cycle();

    lookup_only(32'h1234_5678); // should hit addr 2
    idle_cycle();

    // 6) Same-cycle write + lookup hazard check
    // TB assumes PRE-WRITE lookup semantics, so first response should be miss
    step(1'b1, 6'd20, 32'hFACE_CAFE, 1'b1, 32'hFACE_CAFE);
    idle_cycle();

    // Now it should hit
    lookup_only(32'hFACE_CAFE);
    idle_cycle();

    // 7) Random stress
    repeat (300) begin
      random_cycle();
    end

    // Flush last queued response
    idle_cycle();

    if (errors == 0) begin
      $display("========================================");
      $display("TEST PASSED");
      $display("========================================");
    end
    else begin
      $display("========================================");
      $display("TEST FAILED : %0d error(s)", errors);
      $display("========================================");
      $fatal(1);
    end

    $finish;
  end

endmodule