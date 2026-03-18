`timescale 1ns/1ps

module rr_arb
#(
    parameter int NUM_INPUTS = 4
)
(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  sel_next_i,
    input  logic [NUM_INPUTS-1:0] upstream_ready_i,
    output logic [NUM_INPUTS-1:0] upstream_grant_o,
    input  logic                  downstream_ready_i
);

localparam int NUM_INPUTS_W = (NUM_INPUTS > 1) ? $clog2(NUM_INPUTS) : 1;

logic [NUM_INPUTS-1:0] upstream_ready;
logic [NUM_INPUTS-1:0] shifted_inp;
logic [(2*NUM_INPUTS)-1:0] shifted_pair;
logic [NUM_INPUTS_W-1:0] priority_winner;
logic [NUM_INPUTS_W-1:0] shift;
logic [NUM_INPUTS_W:0]   grant_index;
logic [NUM_INPUTS_W-1:0] grant_index_mod;
logic                    winner_chosen;

assign upstream_ready = sel_next_i ? upstream_ready_i : '0;
assign shifted_pair = {upstream_ready, upstream_ready} >> shift;
assign shifted_inp  = shifted_pair[NUM_INPUTS-1:0];

always_comb begin
    priority_winner = '0;
    winner_chosen   = |shifted_inp;
    grant_index     = '0;
    grant_index_mod = '0;
    upstream_grant_o = '0;

    for (int i = NUM_INPUTS-1; i >= 0; i--) begin
        if (shifted_inp[i]) begin
            priority_winner = i[NUM_INPUTS_W-1:0];
        end
    end

    if (winner_chosen) begin
        grant_index = {1'b0, priority_winner} + {1'b0, shift};
        if (grant_index < NUM_INPUTS) begin
            grant_index_mod = grant_index[NUM_INPUTS_W-1:0];
        end else begin
            grant_index_mod = grant_index[NUM_INPUTS_W-1:0] - NUM_INPUTS[NUM_INPUTS_W-1:0];
        end
        upstream_grant_o[grant_index_mod] = 1'b1;
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        shift <= '0;
    end else if (downstream_ready_i && winner_chosen) begin
        if (grant_index_mod == NUM_INPUTS-1) begin
            shift <= '0;
        end else begin
            shift <= grant_index_mod + 1'b1;
        end
    end
end

endmodule
