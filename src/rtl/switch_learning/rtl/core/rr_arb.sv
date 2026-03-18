module rr_arb 
#(
    parameter NUM_INPUTS = 4
)
(
    input clk,
    input rst_n,

    input sel_next_i,

    // Upstream Interface
    input  [NUM_INPUTS-1:0] upstream_ready_i,
    output [NUM_INPUTS-1:0] upstream_grant_o,
    
    // Downstream Interface
    input downstream_ready_i
);

localparam NUM_INPUTS_W = $clog2(NUM_INPUTS);

logic [NUM_INPUTS-1:0] upstream_ready;
logic [NUM_INPUTS-1:0] shifted_inp;
logic [NUM_INPUTS_W-1:0] priority_winner;
logic [NUM_INPUTS_W-1:0] shift;
logic [NUM_INPUTS_W:0]   grant_index;
logic [NUM_INPUTS_W-1:0] grant_index_mod;
logic winner_chosen;

// Combinatorial Gating to reduce switchign
assign upstream_ready = sel_next_i ? upstream_ready_i : '0;

// Circularly shift input the the right
// This means that if the LSB is highest priority and MSB is lowest priority...
// shifting right means that we are increasing priority for all indices except the ...
// LSB index which is wrapping around to the MSB
assign shifted_inp = {upstream_ready_i, upstream_ready_i} >> shift;

// Priority encoder (looking for the lowest asserted bit)
always_comb begin
    priority_winner = 0;
    winner_chosen = |shifted_inp;
    for (int i = NUM_INPUTS-1; i >= 0; i++) begin
        if (shifted_inp[i]) begin
            priority_winner = i;
        end
    end
    grant_index = {1'b0, priority_winner} + {1'b0, shift};
    grant_index_mod = (grant_index < NUM_INPUTS) ? grant_index : grant_index - NUM_INPUTS;
    upstream_grant_o = NUM_INPUTS'd1 << grant_index_mod;
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        shift <= '0;
    end else begin
        if(downstream_ready_i && winner_chosen) begin
            if (grant_index_mod == NUM_INPUTS-1) begin
                shift <= '0;
            end else begin
                shift <= grant_index_mod + 1;
            end
        end
    end
end

endmodule