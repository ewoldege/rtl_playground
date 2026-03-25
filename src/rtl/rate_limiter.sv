// Exercise 6: Token-bucket rate limiter for a ready/valid stream
// Problem statement

// Design a parameterized RTL module that sits between an upstream producer and downstream consumer and limits the long-term output bandwidth while still allowing short bursts.

// The module shall use a token bucket algorithm:

// tokens accumulate over time at a programmable rate
// each transmitted word consumes a programmable number of tokens
// transmission is allowed only when enough tokens are available
// the bucket has a configurable maximum depth so tokens cannot accumulate without bound

// This models a very common shaping/throttling function used in networking, DMA, memory scheduling, and QoS enforcement.

`timescale 1ns/1ps
module rate_limiter #(
    parameter int W = 32,
    parameter int RATE_W = 8
)
(
    input  logic              clk,
    input  logic              rst_n,

    // upstream side
    output logic              ready_o,
    input  logic              valid_i,
    input  logic [W-1:0]      data_i,

    // downstream side
    input  logic              ready_i,
    output logic              valid_o,
    output logic [W-1:0]      data_o,

    // Configuration Information
    input logic [RATE_W-1:0]  token_add_i,     // tokens added per cycle
    input logic [RATE_W-1:0]  token_cost_i,    // tokens consumed per output beat
    input logic [RATE_W-1:0]  bucket_max_i    // max token count
);

    logic [RATE_W:0] cred_count_next;
    logic [RATE_W-1:0] cred_count;
    logic cred_available;
    logic in_fire, out_fire;
    logic skid_valid;
    logic [W-1:0] skid_data;
    logic valid;
    logic [W-1:0] data;

    // Credit incrementer : Every cycle we are incrementing by a fixed token amount
    // On cycles where we output data, we will decrement by the token cost of the beat
    // Newly added credits will be avaialble for use on the next cycle!
    assign cred_count_next = out_fire ? 
            ({1'b0, cred_count} + {1'b0, token_add_i} - {1'b0, token_cost_i}) : ({1'b0, cred_count} + {1'b0, token_add_i});
    assign cred_available = cred_count >= token_cost_i;
    assign ready_o = ~skid_valid;
    assign in_fire = ready_o && valid_i;
    assign out_fire = ready_i && valid_o;

    
    // Saturating credit counter
    always_ff @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            cred_count <= '0;
        end else begin
            if(cred_count_next > bucket_max_i) begin
                cred_count <= bucket_max_i;
            end else begin
                cred_count <= cred_count_next[RATE_W-1:0];
            end
        end
    end

    // Two entry skid buffer to allow for sustained throughput and decoupled ready
    always_ff @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            valid <= 1'b0;
            skid_valid <= 1'b0;
        end else begin
            if(out_fire && in_fire) begin
                valid <= 1'b1;
                data <= data_i;
            end else if(out_fire) begin
                if(skid_valid) begin
                    valid <= 1'b1;
                    data <= skid_data;
                    skid_valid <= 1'b0;
                end else begin
                    valid <= 1'b0;
                end
            end else if(in_fire) begin
                if(valid) begin
                    skid_valid <= 1'b1;
                    skid_data <= data_i;
                end else begin
                    valid <= 1'b1;
                    data <= data_i;
                end
            end
        end
    end

    assign valid_o = cred_available && valid;
    assign data_o = data;
endmodule; 
