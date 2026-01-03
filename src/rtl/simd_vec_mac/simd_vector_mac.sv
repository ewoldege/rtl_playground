module simd_vector_mac
#(
    parameter int NUM_LANES = 4,
    parameter int ELEM_W = 16,
    parameter int MAX_NUM_ELEM = 64,
    parameter int VEC_MAC_DATA_W = 2*ELEM_W+$clog2(MAX_NUM_ELEM)
)
(

    input clk,
    input rst_n,

    input valid_i,
    input start_i,
    input last_i,
    // output ready_o,
    input logic signed [NUM_LANES-1:0][ELEM_W-1:0] A,
    input logic signed [NUM_LANES-1:0][ELEM_W-1:0] B,
    
    output vector_mac_valid_o,
    // output ready_i
    output logic signed [VEC_MAC_DATA_W-1:0] vector_mac_data_o
    
);

localparam int MULTIPLIER_LATENCY = 2 + $clog2(ELEM_W / 2 + 1);
localparam int LANE_SUM_LATENCY = $clog2(NUM_LANES / 2 + 1);
localparam int METADATA_SHIFT_REG_W = MULTIPLIER_LATENCY + LANE_SUM_LATENCY;
localparam int PRODUCT_W = 2*ELEM_W;
localparam int LANE_SUM_W = PRODUCT_W + $clog2(NUM_LANES);

logic signed[NUM_LANES-1:0][PRODUCT_W-1:0] product;
logic [NUM_LANES-1:0] product_valid;
logic [METADATA_SHIFT_REG_W-1:0] start_shift, last_shift;
logic signed [LANE_SUM_W-1:0] sum_of_lanes;
logic sum_of_lanes_valid;
logic accum_valid;
logic signed [VEC_MAC_DATA_W-1:0] accum;

always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        start_shift <= '0;
        last_shift  <= '0;
    end else begin
        start_shift[METADATA_SHIFT_REG_W-1:1] <= start_shift[METADATA_SHIFT_REG_W-2:0];
        start_shift[0] <= start_i;
        last_shift[METADATA_SHIFT_REG_W-1:1] <= last_shift[METADATA_SHIFT_REG_W-2:0];
        last_shift[0] <= last_i;
    end
end

genvar i;
generate
  for (i = 0; i < NUM_LANES; i = i + 1) begin : gen_blocks
    booth_enc_multiplier #(
        .MULT_W(ELEM_W)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_i        (valid_i),
        .multiplier_i   (A[i]),
        .multiplicand_i (B[i]),
        .product_valid_o(product_valid[i]),
        .product_o      (product[i])
    );
  end
endgenerate

adder_tree 
#(
    .ELEM_W(PRODUCT_W),
    .NUM_ELEM(NUM_LANES),
    .SUM_W(LANE_SUM_W)
)
u_adder_tree
    (
        .clk (clk),
        .rst_n (rst_n),
        .valid_i(product_valid[0]),
        .adder_tree_in(product),
        .sum_valid_o(sum_of_lanes_valid),
        .sum_o(sum_of_lanes)
    );

always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        accum_valid <= 1'b0;
        accum <= '0;
    end else begin
        if(sum_of_lanes_valid) begin
            if(start_shift[$left(start_shift)]) begin
                accum <= sum_of_lanes;
            end else begin
                accum <= accum + sum_of_lanes;
            end
            accum_valid <= last_shift[$left(last_shift)];
        end else begin
            accum_valid <= 1'b0;
        end
    end
end

assign vector_mac_data_o = accum;
assign vector_mac_valid_o = accum_valid;

endmodule
