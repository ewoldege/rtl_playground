`timescale 1ns/1ps

module tb_rate_limiter;

  localparam int W      = 32;
  localparam int RATE_W = 8;

  logic              clk;
  logic              rst_n;

  logic              ready_o;
  logic              valid_i;
  logic [W-1:0]      data_i;

  logic              ready_i;
  logic              valid_o;
  logic [W-1:0]      data_o;

  logic [RATE_W-1:0] token_add_i;
  logic [RATE_W-1:0] token_cost_i;
  logic [RATE_W-1:0] bucket_max_i;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  rate_limiter #(
    .W     (W),
    .RATE_W(RATE_W)
  ) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .ready_o    (ready_o),
    .valid_i    (valid_i),
    .data_i     (data_i),
    .ready_i    (ready_i),
    .valid_o    (valid_o),
    .data_o     (data_o),
    .token_add_i(token_add_i),
    .token_cost_i(token_cost_i),
    .bucket_max_i(bucket_max_i)
  );

  // --------------------------------------------------------------------------
  // Clock / dump
  // --------------------------------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;

  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_rate_limiter);
  end

  // --------------------------------------------------------------------------
  // Reference model state
  // --------------------------------------------------------------------------
  logic [RATE_W-1:0] model_tokens;
  logic              model_out_valid;
  logic              model_skid_valid;
  logic [W-1:0]      model_out_data;
  logic [W-1:0]      model_skid_data;

  int errors;

  task automatic check_outputs(input string label);
    logic exp_ready;
    logic exp_valid;
    begin
      exp_ready = ~model_skid_valid;
      exp_valid = model_out_valid && (model_tokens >= token_cost_i);

      if (ready_o !== exp_ready) begin
        $display("[%0t] ERROR %s: ready_o exp=%0b got=%0b",
                 $time, label, exp_ready, ready_o);
        errors++;
      end

      if (valid_o !== exp_valid) begin
        $display("[%0t] ERROR %s: valid_o exp=%0b got=%0b",
                 $time, label, exp_valid, valid_o);
        errors++;
      end

      if (model_out_valid && (data_o !== model_out_data)) begin
        $display("[%0t] ERROR %s: data_o exp=0x%08h got=0x%08h",
                 $time, label, model_out_data, data_o);
        errors++;
      end
    end
  endtask

  task automatic model_update;
    logic              model_cred_available;
    logic              model_in_fire;
    logic              model_out_fire;
    logic [RATE_W:0]   tokens_ext;
    logic [RATE_W-1:0] next_tokens;
    logic              next_out_valid;
    logic              next_skid_valid;
    logic [W-1:0]      next_out_data;
    logic [W-1:0]      next_skid_data;
    begin
      model_cred_available = (model_tokens >= token_cost_i);
      model_in_fire        = valid_i && ~model_skid_valid;
      model_out_fire       = ready_i && model_out_valid && model_cred_available;

      tokens_ext = {1'b0, model_tokens} + {1'b0, token_add_i};
      if (model_out_fire) begin
        tokens_ext = tokens_ext - {1'b0, token_cost_i};
      end

      if (tokens_ext > {1'b0, bucket_max_i}) begin
        next_tokens = bucket_max_i;
      end else begin
        next_tokens = tokens_ext[RATE_W-1:0];
      end

      next_out_valid  = model_out_valid;
      next_skid_valid = model_skid_valid;
      next_out_data   = model_out_data;
      next_skid_data  = model_skid_data;

      if (model_out_fire) begin
        if (model_skid_valid) begin
          next_out_valid  = 1'b1;
          next_out_data   = model_skid_data;
          next_skid_valid = 1'b0;
        end else if (model_in_fire) begin
          next_out_valid = 1'b1;
          next_out_data  = data_i;
        end else begin
          next_out_valid = 1'b0;
        end
      end else if (model_in_fire) begin
        if (model_out_valid) begin
          next_skid_valid = 1'b1;
          next_skid_data  = data_i;
        end else begin
          next_out_valid = 1'b1;
          next_out_data  = data_i;
        end
      end

      model_tokens     = next_tokens;
      model_out_valid  = next_out_valid;
      model_skid_valid = next_skid_valid;
      model_out_data   = next_out_data;
      model_skid_data  = next_skid_data;
    end
  endtask

  task automatic step(
    input logic              next_valid_i,
    input logic [W-1:0]      next_data_i,
    input logic              next_ready_i,
    input logic [RATE_W-1:0] next_token_add_i,
    input logic [RATE_W-1:0] next_token_cost_i,
    input logic [RATE_W-1:0] next_bucket_max_i,
    input string             label
  );
    begin
      @(negedge clk);
      valid_i     = next_valid_i;
      data_i      = next_data_i;
      ready_i     = next_ready_i;
      token_add_i = next_token_add_i;
      token_cost_i = next_token_cost_i;
      bucket_max_i = next_bucket_max_i;

      @(posedge clk);
      #1;
      if (!rst_n) begin
        model_tokens     = '0;
        model_out_valid  = 1'b0;
        model_skid_valid = 1'b0;
        model_out_data   = '0;
        model_skid_data  = '0;
      end else begin
        model_update();
      end
      check_outputs(label);
    end
  endtask

  task automatic idle_step(
    input logic [RATE_W-1:0] cfg_add,
    input logic [RATE_W-1:0] cfg_cost,
    input logic [RATE_W-1:0] cfg_max,
    input string             label
  );
    begin
      step(1'b0, '0, 1'b0, cfg_add, cfg_cost, cfg_max, label);
    end
  endtask

  task automatic apply_reset;
    begin
      valid_i        = 1'b0;
      data_i         = '0;
      ready_i        = 1'b0;
      token_add_i    = '0;
      token_cost_i   = '0;
      bucket_max_i   = '0;
      rst_n          = 1'b0;

      model_tokens     = '0;
      model_out_valid  = 1'b0;
      model_skid_valid = 1'b0;
      model_out_data   = '0;
      model_skid_data  = '0;
      errors           = 0;

      repeat (3) @(posedge clk);
      #1;
      check_outputs("during_reset");
      rst_n = 1'b1;
      step(1'b0, '0, 1'b0, 8'd0, 8'd1, 8'd8, "after_reset");
    end
  endtask

  task automatic random_step(input int idx);
    logic              rand_valid_i;
    logic              rand_ready_i;
    logic [W-1:0]      rand_data_i;
    logic [RATE_W-1:0] rand_add;
    logic [RATE_W-1:0] rand_cost;
    logic [RATE_W-1:0] rand_max;
    string             label;
    begin
      rand_valid_i = $urandom_range(0, 1);
      rand_ready_i = $urandom_range(0, 1);
      rand_data_i  = $urandom;
      rand_add     = $urandom_range(0, 4);
      rand_cost    = $urandom_range(1, 6);
      rand_max     = $urandom_range(rand_cost, 15);
      label = $sformatf("random_%0d", idx);
      step(rand_valid_i, rand_data_i, rand_ready_i, rand_add, rand_cost, rand_max, label);
    end
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    int rand_idx;

    apply_reset();

    // 1) Accumulate enough tokens for a blocked beat, then release it.
    step(1'b1, 32'h1111_0001, 1'b1, 8'd1, 8'd3, 8'd5, "accum_0");
    step(1'b0, '0,         1'b1, 8'd1, 8'd3, 8'd5, "accum_1");
    step(1'b0, '0,         1'b1, 8'd1, 8'd3, 8'd5, "accum_2");
    step(1'b0, '0,         1'b1, 8'd1, 8'd3, 8'd5, "accum_3");
    step(1'b0, '0,         1'b1, 8'd1, 8'd3, 8'd5, "accum_4");

    // 2) Saturate the token bucket while idle.
    repeat (6) begin
      step(1'b0, '0, 1'b0, 8'd4, 8'd2, 8'd9, "saturate");
    end

    // 3) Fill output + skid under backpressure, then drain.
    step(1'b1, 32'hAAAA_0001, 1'b0, 8'd8, 8'd1, 8'd12, "skid_fill_0");
    step(1'b1, 32'hAAAA_0002, 1'b0, 8'd8, 8'd1, 8'd12, "skid_fill_1");
    step(1'b1, 32'hAAAA_0003, 1'b0, 8'd8, 8'd1, 8'd12, "skid_full_hold");
    step(1'b0, '0,          1'b1, 8'd8, 8'd1, 8'd12, "skid_drain_0");
    step(1'b0, '0,          1'b1, 8'd8, 8'd1, 8'd12, "skid_drain_1");
    step(1'b0, '0,          1'b1, 8'd8, 8'd1, 8'd12, "skid_drain_2");

    // 4) Mixed random stress with changing configuration.
    for (rand_idx = 0; rand_idx < 300; rand_idx++) begin
      random_step(rand_idx);
    end

    // Flush several cycles so the buffered contents drain.
    repeat (20) begin
      step(1'b0, '0, 1'b1, 8'd3, 8'd1, 8'd15, "flush");
    end

    if (errors == 0) begin
      $display("========================================");
      $display("TEST PASSED");
      $display("========================================");
    end else begin
      $display("========================================");
      $display("TEST FAILED : %0d error(s)", errors);
      $display("========================================");
      $fatal(1);
    end

    $finish;
  end

endmodule
