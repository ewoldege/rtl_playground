// Block latency = 2 + clog2(MULT_W/2+1) + 1
module adder_tree
#(
    parameter int ELEM_W = 16,
    parameter int NUM_ELEM = 16,
    parameter int SUM_W = ELEM_W + clog2(NUM_ELEM)
)
(

    input clk,
    input rst_n,

    input valid_i,
    input logic signed [NUM_ELEM-1:0][ELEM_W-1:0] adder_tree_in, 
    
    output sum_valid_o,
    output logic signed [SUM_W-1:0] sum_o
    
);
localparam int NUM_ELEM_POWER_OF_2 = 2**$clog2(NUM_ELEM);
localparam ADDER_TREE_LEVELS = $clog2(NUM_ELEM_POWER_OF_2) + 1; // Includes staging level

logic [ADDER_TREE_LEVELS-1:0] adder_tree_valid;
logic signed [ADDER_TREE_LEVELS-1:0][NUM_ELEM_POWER_OF_2-1:0][ELEM_W-1:0] adder_tree;

assign adder_tree_valid[0] = valid_i; // Staging level
assign adder_tree[0] = { {(NUM_ELEM_POWER_OF_2-NUM_ELEM){ {(ELEM_W){1'b0}} } }, adder_tree_in };

// Adder Tree
always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        adder_tree_valid[ADDER_TREE_LEVELS-1:1] <= '0;
    end else begin
        adder_tree_valid[ADDER_TREE_LEVELS-1:1] <= adder_tree_valid[ADDER_TREE_LEVELS-2:0];
        for (int i = 1; i < ADDER_TREE_LEVELS; i++) begin
            if(adder_tree_valid[i-1]) begin
                for (int j = 0; j < NUM_ELEM_POWER_OF_2/(2**i); j++) begin
                    adder_tree[i][j] <= adder_tree[i-1][2*j] + adder_tree[i-1][2*j+1];
                end    
            end
        end
    end
end

assign sum_o = adder_tree[ADDER_TREE_LEVELS-1][0];
assign sum_valid_o = adder_tree_valid[ADDER_TREE_LEVELS-1];
endmodule
