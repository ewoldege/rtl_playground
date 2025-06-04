module fixed_point_arithmetic 
#(
    parameter WORD_LENGTH = 16
)
(
    input clk,
    input rst_n,

    input [WORD_LENGTH-1:0] a,
    input [WORD_LENGTH-1:0] b,
    input valid_i,

    output [WORD_LENGTH:0] c_add,
    output [2*WORD_LENGTH-1:0] c_mult,
    output valid_o
);

logic[WORD_LENGTH:0] add;
logic[2*WORD_LENGTH-1:0] mult;

always_ff @( posedge clk ) begin
    if(~rst_n) begin
        add <= '0;
        mult <= '0;
    end else begin
        add <= a + b;
        mult <= a * b;
    end
end

assign c_add = add;
assign c_mult = mult;

endmodule