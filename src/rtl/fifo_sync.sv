module fifo_sync #(
  parameter int DATA_W = 32,
  parameter int DEPTH  = 16
)(
  input  logic                 clk,
  input  logic                 rst_n,   // Active-low async reset

  // Write interface
  input  logic                 wr_en,
  input  logic [DATA_W-1:0]    wr_data,
  output logic                 full,

  // Read interface
  input  logic                 rd_en,
  output logic [DATA_W-1:0]    rd_data,
  output logic                 empty
);

  // ------------------------------------------------------------
  // Local parameters
  // ------------------------------------------------------------
  localparam int ADDR_W = $clog2(DEPTH);

  // ------------------------------------------------------------
  // Storage
  // ------------------------------------------------------------
  logic [DATA_W-1:0] mem [0:DEPTH-1];

  logic [ADDR_W-1:0] wr_ptr;
  logic [ADDR_W-1:0] rd_ptr;
  logic [ADDR_W:0]   count;   // Needs to count up to DEPTH

  // ------------------------------------------------------------
  // Status flags
  // ------------------------------------------------------------
  assign full  = (count == DEPTH);
  assign empty = (count == 0);

  // ------------------------------------------------------------
  // Write logic
  // ------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
    end else if (wr_en && !full) begin
      mem[wr_ptr] <= wr_data;
      if (wr_ptr == DEPTH-1)
        wr_ptr <= '0;
      else
        wr_ptr <= wr_ptr + 1'b1;
    end
  end

  // ------------------------------------------------------------
  // Read logic
  // ------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr  <= '0;
      rd_data <= '0;
    end else if (rd_en && !empty) begin
      rd_data <= mem[rd_ptr];
      if (rd_ptr == DEPTH-1)
        rd_ptr <= '0;
      else
        rd_ptr <= rd_ptr + 1'b1;
    end
  end

  // ------------------------------------------------------------
  // Count logic (handles simultaneous R/W)
  // ------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= '0;
    end else begin
      case ({wr_en && !full, rd_en && !empty})
        2'b10: count <= count + 1'b1;  // write only
        2'b01: count <= count - 1'b1;  // read only
        default: count <= count;       // no change or simultaneous
      endcase
    end
  end

endmodule
