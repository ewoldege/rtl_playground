import sparse_mac_pkg::*;

module sparse_mac_top
#(
    parameter NUM_DECODERS = 2
)
(

    input mac_clk,
    input mac_rst,

    // Input SRAM Ready Valid Interface
    input[NUM_DECODERS-1:0] sram_valid_i,
    output[NUM_DECODERS-1:0] sram_ready_o,
    // Data struct from SRAM block
    sram_data_t[NUM_DECODERS-1:0] sram_data_i,

    // Output Comparison Ready/Valid interface
    output mac_valid_o,
    // Data struct to comparison block
    output [ACCUM_W-1:0] mac_data_o
    
);

logic[NUM_DECODERS-1:0] decoder_valid;
logic[NUM_DECODERS-1:0] decoder_ready;
decoder_data_t[NUM_DECODERS-1:0] decoder_data;

genvar i;
generate
    for (i = 0; i < NUM_DECODERS; i++) begin : decoder_gen
        decoder decoder_inst (
            .mac_clk(mac_clk),
            .mac_rst(mac_rst),
            .sram_valid_i(sram_valid_i[i]),
            .sram_ready_o(sram_ready_o[i]),
            .sram_data_i(sram_data_i[i]),
            .decoder_valid_o(decoder_valid[i]),
            .decoder_ready_i(decoder_ready[i]),
            .decoder_data_o(decoder_data[i])
        );
    end
endgenerate

logic comparator_valid;
logic comparator_done;
value_bus_t[NUM_DECODERS-1:0] comparator_data;

  comparator #(
    .NUM_DECODERS(NUM_DECODERS)
  )
  u_comparator (
    .mac_clk(mac_clk),
    .mac_rst(mac_rst),

    .decoder_valid_i(decoder_valid),
    .decoder_ready_o(decoder_ready),
    .decoder_data_i (decoder_data),

    .mac_valid_o(comparator_valid),
    .mac_finish_o(comparator_done),
    .mac_data_o (comparator_data)
  );

  multiply_and_accum #(
    .NUM_DECODERS(NUM_DECODERS)
  )
  u_mac
  (
    .mac_clk(mac_clk),
    .mac_rst(mac_rst),

    .comparator_valid_i(comparator_valid),
    .comparator_done_i(comparator_done),
    .comparator_data_i (comparator_data),

    .mac_valid_o(mac_valid_o),
    .mac_data_o(mac_data_o)
  );

endmodule
