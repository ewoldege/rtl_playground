module fixed_point_arithmetic 
#(
    parameter WORD_LENGTH = 16
)
(
    input clk,
    input rst_n,

    input logic signed[WORD_LENGTH-1:0] a,
    input logic signed[WORD_LENGTH-1:0] b,
    input valid_i,

    output logic signed[WORD_LENGTH:0] c_add,
    output logic signed[2*WORD_LENGTH-1:0] c_mult,
    output logic signed[3:0] c_clipped_add,
    output logic signed[WORD_LENGTH-3:0] c_round_add,
    output valid_o
);

logic signed [WORD_LENGTH:0] add, add_temp;
logic signed [2*WORD_LENGTH-1:0] mult;
logic valid;
logic upper_bits_set;

always_ff @( posedge clk ) begin
    if(~rst_n) begin
        add <= '0;
        mult <= '0;
        valid <= 1'b0;
    end else begin
        add <= $signed(a) + $signed(b);
        mult <= $signed(a) * $signed(b);
        valid <= valid_i;
    end
end
/* verilator lint_off WIDTHEXPAND */
assign add_temp = add[WORD_LENGTH] ? (add - 4) : (add + 4);
/* verilator lint_on WIDTHEXPAND */
assign c_round_add = add_temp[WORD_LENGTH:3];
// Checks to see if the upper bits of the add bus are set.
// In the case of negative bus value, We expect MSB to be set, but at least one of the other bits to be 0
assign upper_bits_set = ~(&add[WORD_LENGTH:3] | &(~add[WORD_LENGTH:3]));
assign c_clipped_add[3] = add[WORD_LENGTH];
assign c_clipped_add[2:0] = upper_bits_set ? (add[WORD_LENGTH] ? '0 : '1) : add[2:0];

assign c_add = add;
assign c_mult = mult;
assign valid_o = valid;

endmodule