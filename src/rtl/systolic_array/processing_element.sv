module processing_element
#(
    parameter int ACCUM_W = 32,
    parameter int WEIGHT_W = 8,
    parameter int ACTIVATION_W = 8
)
(
    input clk,
    input rst_n,

    input logic weight_load_in;
    input logic [WEIGHT_W-1:0] weight_in;

    // It is assumed that when the activation is valid,
    // the input accumulator is also valid
    // We are putting the owness on the orchestrator to ensure this
    input logic valid_in,
    input logic [ACTIVATION_W-1:0] activation_in,
    input logic [ACCUM_W-1:0]      accum_in,

    output logic valid_out,
    output logic [ACTIVATION_W-1:0] activation_out,
    output logic accum_valid_out,
    output logic [ACCUM_W-1:0]      accum_out,
);

logic [WEIGHT_W-1:0] weight_val;

always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        weight_val <= '0;
        valid_out <= '0;
    end else begin
        if(weight_load_in)
            weight_val <= weight_in;
        valid_out <= valid_in
        if (valid_in) begin
            activation_out <= activation_in;
            // 8x8 multiply = 16 bit
            // 16+8 multiply = 17 bit
            // Fits easily inside a 32-bit bus
            accum_out <= activation_in*weight_val + accum_in;
        end

    end
end

endmodule