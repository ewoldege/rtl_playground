`timescale 1ns/1ps
import systolic_array_pkg::*;

module banked_accum
#(
    parameter int ACCUM_W = 32,
    parameter int ARRAY_W = 4,
    parameter int MAT_W_W = 4
)
(
    input clk,
    input rst_n,

    input inc_valid,
    input logic [MAT_W_W-1:0] inc_addr,
    input logic [ARRAY_W-1:0][ACCUM_W-1:0] inc_data,

    // For draining results
    // Note, when draining results, banked accumulator must be disabled
    // Because we are utilizing the read port for the draining
    // We could expand this to true dual port memory if we wanted a dedicated
    // drain port
    input rd_en,
    input  logic [MAT_W_W-1:0] rd_addr,
    output logic [2*ACCUM_W-1:0] rd_data
);

logic[ARRAY_W-1:0][ACCUM_W-1:0] inc_data_q;
logic[ARRAY_W-1:0][ACCUM_W-1:0] sram_rdata;
logic[ARRAY_W-1:0][ACCUM_W-1:0] banked_accum;
logic[MAT_W_W-1:0] sram_rd_addr;
logic[MAT_W_W-1:0] inc_addr_q;
logic[MAT_W_W-1:0] inc_addr_2q;
logic sram_rvalid;
logic sram_is_valid;

sram_cell #(
    .DATA_W(ARRAY_W*ACCUM_W),
    .DEPTH(MAT_W)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .en(1'b1),
    .wr_en(banked_accum_valid),
    .wr_addr(inc_addr_2q),
    .wr_data(banked_accum),
    .byte_en('1),
    .rd_en(inc_valid),
    .rd_addr(sram_rd_addr),
    .rd_data(sram_rdata),
    .rd_valid(sram_rvalid)    
);

// Overrides read port when drain is enabled
assign sram_rd_addr = rd_en ? rd_addr : inc_addr;
assign rd_data = sram_rdata;

always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        banked_accum_valid <= 1'b0;
        sram_is_valid <= 1'b0;
    end else begin
        inc_addr_q <= inc_addr;
        inc_addr_2q <= inc_addr_q;
        inc_data_q <= inc_data;
        banked_accum_valid <= sram_rvalid;
        
        // Indicates when a full pass through the SRAM has been completed
        // Assumes sequential access nature through SRAM
        // Full pass through means that we have some level of history in SRAM for the accumulation
        // If this isnt enabled, then just write the current increment value as the history in SRAM
        if(inc_valid && (inc_addr == MAT_W-1))
            sram_is_valid <= 1'b1;
    end
end


// Banked Accumulator
for(genvar j = 0; j < ARRAY_W; j++) begin
    always_ff @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
        end else begin
            // When the systolic array has an element, add it to the running accumulator
            if(sram_rvalid)
                if(sram_is_valid)
                    banked_accum[j] <= sram_rdata[j] + inc_data_q[j];
                else
                    banked_accum[j] <= inc_data_q[j];
        end
    end
end

endmodule
 