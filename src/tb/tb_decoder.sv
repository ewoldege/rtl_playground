`timescale 1ns/1ps

import sparse_mac_pkg::*;

module tb_decoder;

  // Clock / Reset
  logic mac_clk;
  logic mac_rst;

  // SRAM interface
  logic        sram_valid_i;
  logic        sram_ready_o;
  sram_data_t  sram_data_i;

  // Decoder output interface
  logic          decoder_valid_o;
  logic          decoder_ready_i;
  decoder_data_t decoder_data_o;

  // DUT
  decoder dut (
    .mac_clk(mac_clk),
    .mac_rst(mac_rst),

    .sram_valid_i(sram_valid_i),
    .sram_ready_o(sram_ready_o),
    .sram_data_i (sram_data_i),

    .decoder_valid_o(decoder_valid_o),
    .decoder_ready_i(decoder_ready_i),
    .decoder_data_o (decoder_data_o)
  );

  // Clock generation
  always #5 mac_clk = ~mac_clk;

  // ----------------------------
  // Golden model state
  // ----------------------------
  int unsigned golden_index;

  typedef struct {
    int unsigned index;
    int unsigned value;
  } exp_t;

  exp_t expected_q[$];

  // ----------------------------
  // Reset
  // ----------------------------
  task automatic reset_dut();
    mac_rst = 1;
    sram_valid_i = 0;
    decoder_ready_i = 0;
    golden_index = 0;
    expected_q.delete();
    repeat (5) @(posedge mac_clk);
    mac_rst = 0;
  endtask

  // ----------------------------
  // Drive one SRAM transaction
  // ----------------------------
  task automatic send_sram(input int skip, input int value);
    sram_data_i.skip  = skip;
    sram_data_i.value = value;
    sram_valid_i      = 1;

    // Wait until accepted
    do @(posedge mac_clk);
    while (!(sram_valid_i && sram_ready_o));

    // Update golden model
    golden_index += skip;
    expected_q.push_back('{ index: golden_index, value: value });
    golden_index += 1;

    sram_valid_i = 0;
  endtask

  // ----------------------------
  // Consume decoder output
  // ----------------------------
  task automatic consume_outputs();
    exp_t exp;

    forever begin
      @(posedge mac_clk);

      if (decoder_valid_o && decoder_ready_i) begin
        if (expected_q.size() == 0) begin
          $error("Unexpected decoder output: index=%0d value=%0d",
                  decoder_data_o.index, decoder_data_o.value);
        end else begin
          exp = expected_q.pop_front();

          if (decoder_data_o.index !== exp.index ||
              decoder_data_o.value !== exp.value) begin
            $error("Mismatch! Expected (idx=%0d val=%0d), Got (idx=%0d val=%0d)",
                    exp.index, exp.value,
                    decoder_data_o.index, decoder_data_o.value);
          end else begin
            $display("[OK] index=%0d value=%0d",
                     decoder_data_o.index, decoder_data_o.value);
          end
        end
      end
    end
  endtask

  // ----------------------------
  // Random backpressure
  // ----------------------------
  always @(posedge mac_clk) begin
    if (mac_rst)
      decoder_ready_i <= 0;
    else
      decoder_ready_i <= $urandom_range(0,1);
  end

  // ----------------------------
  // Test sequence
  // ----------------------------
  initial begin
    mac_clk = 0;
    reset_dut();

    fork
      consume_outputs();
    join_none

    // Example from problem statement
    send_sram(5, 3);
    send_sram(4, 6);

    // Additional stress cases
    send_sram(0, 9);   // back-to-back nonzeros
    send_sram(10, 1);  // large skip
    send_sram(1, 7);

    // Let outputs drain
    repeat (50) @(posedge mac_clk);

    if (expected_q.size() != 0) begin
      $error("Test ended with %0d expected outputs remaining",
              expected_q.size());
    end else begin
      $display("TEST PASSED");
    end

    $finish;
  end

endmodule
