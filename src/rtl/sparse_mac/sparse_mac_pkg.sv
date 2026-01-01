package sparse_mac_pkg;
  // Use 'packed' for I/O ports to ensure bit-level compatibility
  localparam int VALUE_W = 16;
  localparam int INDEX_W = 16;
  localparam int DECODER_FIFO_DEPTH = 16;
  localparam int DECODER_OUTPUT_BUFFER_SIZE = 4;
  localparam int DECODER_BUFFER_FIFO_LATENCY = 3;
  localparam int NUM_DECODERS = 2;
  localparam int ACCUM_W = 32;

  typedef logic[VALUE_W-1:0] value_bus_t;
  typedef logic[INDEX_W-1:0] index_bus_t;

  typedef struct packed {
    logic done;
    value_bus_t value;
    index_bus_t skip;
  } sram_data_t;

  typedef struct packed {
    logic done;
    value_bus_t value;
    index_bus_t index;
  } decoder_data_t;
endpackage