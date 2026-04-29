`timescale 1ns/1ps
import systolic_array_pkg::*;

module banked_accum
#(
    parameter int ACCUM_W = 32,
    parameter int ARRAY_W = 4,
    parameter int MAT_W = 4,
    parameter int MAT_W_W = $clog2(MAT_W)
)
(
    input logic clk,
    input logic rst_n,
    input logic clr,

    input logic inc_valid,
    input logic [MAT_W_W-1:0] inc_addr,
    input logic [ARRAY_W-1:0][ACCUM_W-1:0] inc_data,

    // For draining results
    // Note, when draining results, banked accumulator must be disabled
    // Because we are utilizing the read port for the draining
    // We could expand this to true dual port memory if we wanted a dedicated
    // drain port
    input  logic drain_rd_en,
    input  logic [MAT_W_W-1:0] drain_rd_addr,
    output logic [ARRAY_W-1:0][ACCUM_W-1:0] drain_rd_data
);

logic[ARRAY_W-1:0][ACCUM_W-1:0] inc_data_q;
logic[ARRAY_W-1:0][ACCUM_W-1:0] sram_rdata;
logic[ARRAY_W-1:0][ACCUM_W-1:0] banked_accum;
logic[MAT_W_W-1:0] sram_rd_addr;
logic[MAT_W_W-1:0] inc_addr_q;
logic[MAT_W_W-1:0] inc_addr_2q;
logic banked_accum_valid;
logic sram_rd_en;
logic sram_rvalid;
logic sram_is_valid;
logic inc_valid_q;
logic drain_rd_en_q;
logic drain_rd_en_2q;

sram_cell #(
    .DATA_W(ARRAY_W*ACCUM_W),
    .DEPTH(MAT_W)
) sram (
    .clk(clk),
    .rst_n(rst_n),
    .en(1'b1),
    .wr_en(banked_accum_valid),
    .wr_addr(inc_addr_2q),
    .wr_data(banked_accum),
    .byte_en('1),
    .rd_en(sram_rd_en),
    .rd_addr(sram_rd_addr),
    .rd_data(sram_rdata),
    .rd_valid(sram_rvalid)    
);

// Overrides read port when drain is enabled
assign sram_rd_en = (inc_valid && sram_is_valid) || drain_rd_en;
assign sram_rd_addr = drain_rd_en ? drain_rd_addr : inc_addr;
// Comb gating to prevent downstream toggling
assign drain_rd_data = drain_rd_en_q ? sram_rdata : '0;

always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        banked_accum_valid <= 1'b0;
        sram_is_valid <= 1'b0;
        drain_rd_en_q <= 1'b0;
        drain_rd_en_2q <= 1'b0;
        inc_addr_q <= '0;
        inc_addr_2q <= '0;
        inc_valid_q <= 1'b0;
    end else begin
        if(clr) begin
            sram_is_valid <= 1'b0;
        end else begin
            inc_addr_q <= inc_addr;
            inc_addr_2q <= inc_addr_q;
            inc_data_q <= inc_data;
            // We are only writing back to SRAM when we are in accumulation mode, not drain
            banked_accum_valid <= ~drain_rd_en_q && inc_valid_q;
            drain_rd_en_q <= drain_rd_en;
            drain_rd_en_2q <= drain_rd_en_q;
            inc_valid_q <= inc_valid;
            
            // Indicates when a full pass through the SRAM has been completed
            // Assumes sequential access nature through SRAM
            // Full pass through means that we have some level of history in SRAM for the accumulation
            // If this isnt enabled, then just write the current increment value as the history in SRAM
            if(inc_valid && (inc_addr == MAT_W-1))
                sram_is_valid <= 1'b1;
        end
    end
end


// Banked Accumulator
for(genvar j = 0; j < ARRAY_W; j++) begin
    always_ff @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
        end else begin
            // When the systolic array has an element, add it to the running accumulator
            if(sram_rvalid)
                banked_accum[j] <= sram_rdata[j] + inc_data_q[j];
            else
                banked_accum[j] <= inc_data_q[j];
        end
    end
end

endmodule
 