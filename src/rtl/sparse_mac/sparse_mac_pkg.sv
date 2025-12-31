package sparse_mac_pkg;
  // Use 'packed' for I/O ports to ensure bit-level compatibility
  localparam int VALUE_W = 16;
  localparam int INDEX_W = 16;
  localparam int DECODER_FIFO_DEPTH = 16;
  localparam int DECODER_OUTPUT_BUFFER_SIZE = 4;
  localparam int DECODER_BUFFER_FIFO_LATENCY = 3;

  typedef struct packed {
    logic [VALUE_W-1:0] value;
    logic [INDEX_W-1:0] skip;
  } sram_data_t;

  typedef struct packed {
    logic [VALUE_W-1:0] value;
    logic [INDEX_W-1:0] index;
  } decoder_data_t;
endpackage