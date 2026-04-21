`timescale 1ns/1ps

module sram_cell #(
    parameter int DATA_W = 32,
    parameter int DEPTH  = 1024,
    parameter int ADDR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter int BYTE_W = 8,
    parameter int BYTE_EN_W = (DATA_W + BYTE_W - 1) / BYTE_W,

    // Read-during-write behavior when rd_en and wr_en hit the same address:
    //   0: READ_FIRST  - read returns the old memory contents
    //   1: WRITE_FIRST - read returns the newly written contents
    //   2: NO_CHANGE   - read data holds its previous value
    parameter int RDW_MODE = 0
)(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  en,
    input  logic                  wr_en,
    input  logic [ADDR_W-1:0]     wr_addr,
    input  logic [DATA_W-1:0]     wr_data,
    input  logic [BYTE_EN_W-1:0]  byte_en,

    input  logic                  rd_en,
    input  logic [ADDR_W-1:0]     rd_addr,
    output logic [DATA_W-1:0]     rd_data,
    output logic                  rd_valid
);

    localparam int READ_FIRST  = 0;
    localparam int WRITE_FIRST = 1;
    localparam int NO_CHANGE   = 2;

    logic [DATA_W-1:0] mem [0:DEPTH-1];

    function automatic logic [DATA_W-1:0] apply_byte_en(
        input logic [DATA_W-1:0] old_data,
        input logic [DATA_W-1:0] new_data,
        input logic [BYTE_EN_W-1:0] be
    );
        logic [DATA_W-1:0] merged_data;
        begin
            merged_data = old_data;
            for (int i = 0; i < DATA_W; i++) begin
                if (be[i / BYTE_W]) begin
                    merged_data[i] = new_data[i];
                end
            end
            return merged_data;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data  <= '0;
            rd_valid <= 1'b0;
            // TODO: Remove memory reset once callers no longer depend on cleared SRAM contents.
            for (int i = 0; i < DEPTH; i++) begin
                mem[i] <= '0;
            end
        end else begin
            rd_valid <= en && rd_en;

            if (en && rd_en) begin
                if (wr_en && (wr_addr == rd_addr) && (RDW_MODE == WRITE_FIRST)) begin
                    rd_data <= apply_byte_en(mem[rd_addr], wr_data, byte_en);
                end else if (!(wr_en && (wr_addr == rd_addr) && (RDW_MODE == NO_CHANGE))) begin
                    rd_data <= mem[rd_addr];
                end
            end

            if (en && wr_en) begin
                mem[wr_addr] <= apply_byte_en(mem[wr_addr], wr_data, byte_en);
            end
        end
    end

endmodule
