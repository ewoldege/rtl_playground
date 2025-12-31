module fifo_fwft_sync #(
    parameter int DATA_W = 16,         // Data width
    parameter int DEPTH  = 16          // FIFO depth
)(
    input  logic               clk,
    input  logic               rst_n,      // active low async reset
    input  logic               wr_en,
    input  logic [DATA_W-1:0] wr_data,
    output logic               full,
    input  logic               rd_en,
    output logic [DATA_W-1:0] rd_data,
    output logic               empty
);

    // Internal storage
    logic [DATA_W-1:0] mem [0:DEPTH-1];

    // Pointers
    logic [$clog2(DEPTH)-1:0] wr_ptr, rd_ptr;
    logic [$clog2(DEPTH):0]   fifo_count;  // extra bit to distinguish full vs empty

    // Empty/Full flags
    assign empty = (fifo_count == 0);
    assign full  = (fifo_count == DEPTH);

    // First-word fall-through: output always reflects memory at rd_ptr if not empty
    assign rd_data = mem[rd_ptr];

    // Write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= '0;
        end else if (wr_en && !full) begin
            mem[wr_ptr] <= wr_data;
            wr_ptr      <= wr_ptr + 1;
        end
    end

    // Read pointer and fifo count logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr     <= '0;
            fifo_count <= '0;
        end else begin
            // Update fifo_count
            case ({wr_en && !full, rd_en && !empty})
                2'b10: fifo_count <= fifo_count + 1; // write only
                2'b01: fifo_count <= fifo_count - 1; // read only
                default: fifo_count <= fifo_count;   // read+write or idle
            endcase

            // Update read pointer
            if (rd_en && !empty)
                rd_ptr <= rd_ptr + 1;
        end
    end

endmodule
