module lpf 
#(
    parameter TAP_NUM = 16,
    parameter SAMPLE_LEN = 16,
    parameter COEFFICIENT_LEN = 16
)
(
    input clk,
    input rst_n,

    input signed [SAMPLE_LEN-1:0] sample_i,
    input signed [TAP_NUM-1:0][COEFFICIENT_LEN-1:0] coeff_i

);

localparam L_MULT_LENGTH = SAMPLE_LEN + COEFFICIENT_LEN;

logic signed [TAP_NUM:0][SAMPLE_LEN-1:0] sample_sr;
logic signed [TAP_NUM-1:0][L_MULT_LENGTH-1:0] multiplier;
int i;

for (i=0; i<TAP_NUM; i++) begin
    assign multiplier[i] = sample_sr[i] * coeff_i[i];
end

always_ff @( posedge clk ) begin
    if(~rst_n) begin
        sample_sr <= '0;
    end else begin
        sample_sr <= {sample_sr[TAP_NUM-1:0], sample_i};
    end
end

endmodule