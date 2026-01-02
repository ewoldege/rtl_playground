// Block latency = 2 + clog2(MULT_W/2+1) + 1
module booth_enc_multiplier
#(
    parameter int MULT_W = 16,
    parameter int PROD_W = 2*MULT_W
)
(

    input clk,
    input rst_n,

    input valid_i,
    input logic signed [MULT_W-1:0] multiplier_i,
    input logic signed [MULT_W-1:0] multiplicand_i,
    
    output  product_valid_o,
    output logic signed [PROD_W-1:0] product_o
    
);
localparam int NUM_PP = MULT_W/2+1; // Number of Partial Products needed for a safe Radix-4 Booth Multiplier
localparam int MULTIPLICAND_EXT_W = 2*NUM_PP+1;
localparam int PP_W_POWER_OF_2 = 2**$clog2(NUM_PP);

logic signed[MULT_W-1:0] multiplier_q;
logic signed[MULTIPLICAND_EXT_W-1:0] multiplicand_ext;
logic[NUM_PP-1:0][2:0] sel;
logic sel_valid;

// This ensures the multiplicand width is sign extended to an odd WIDTH (3,5,7,9,11,13...)
// It also adds a -1 index for the booth encoding to work properly
// 1. Cast multiplicand_i to MULTIPLICAND_EXT_W width (sign-extends automatically)
// 2. Shift left by 1 to add the Booth '0' at index -1
assign multiplicand_ext = MULTIPLICAND_EXT_W'($signed(multiplicand_i)) << 1;

// Encoding: {2i+1, 2i, 2i-1}
// Since we are adding the [-1] index to index 0, everything is shifted to the left
// Indexing is now {2i+2, 2i+1, 2i}
always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        sel_valid <= 1'b0;
    end else begin
        sel_valid <= valid_i;
        multiplier_q <= multiplier_i;
    end
end

genvar i;
generate
    for (i = 0; i < NUM_PP; i = i + 1) begin : sel_assign
        always_ff @(posedge clk or negedge rst_n) begin
            if (~rst_n)
                sel[i] <= '0;
            else if (valid_i)
                sel[i] <= multiplicand_ext[2*i+2 : 2*i];
        end
    end
endgenerate


logic signed [NUM_PP-1:0][PROD_W-1:0] pp; // 1-bit width growth due to *2
logic pp_valid;

// Partial product generator
always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        pp_valid <= 1'b0;
    end else begin
        pp_valid <= sel_valid;
        if(sel_valid) begin
            for (int i = 0; i < NUM_PP; i++) begin
                // Pre-calculate the shift amount for this partial product
                // pp[0] shifts 0, pp[1] shifts 2, pp[2] shifts 4, etc.
                case (sel[i])
                    3'b000, 3'b111: pp[i] <= '0;
                    // Positive 1x: Cast to 32-bit, then final shift
                    3'b001, 3'b010: pp[i] <= PROD_W'($signed(multiplier_q)) << (2*i);
                    // Positive 2x: Cast to 32-bit FIRST, then multiply by 2 (<<< 1), then final shift
                    3'b011:         pp[i] <= (PROD_W'($signed(multiplier_q)) <<< 1) << (2*i);
                    // Negative 1x: Cast to 32-bit FIRST, then negate, then final shift
                    3'b101, 3'b110: pp[i] <= (-PROD_W'($signed(multiplier_q))) << (2*i);
                    // Negative 2x: Cast to 32-bit FIRST, shift (2x), negate, then final shift
                    3'b100:         pp[i] <= (-(PROD_W'($signed(multiplier_q)) <<< 1)) << (2*i);
                    default:        pp[i] <= '0;
                endcase
            end
        end
    end
end

adder_tree 
#(
    .ELEM_W(PROD_W),
    .NUM_ELEM(NUM_PP),
    .SUM_W(PROD_W)
)
u_adder_tree
    (
        .clk (clk),
        .rst_n (rst),
        .valid_i(pp_valid),
        .adder_tree_in(pp),
        .sum_valid_o(product_valid_o),
        .sum_o(product_o)
    );

endmodule
