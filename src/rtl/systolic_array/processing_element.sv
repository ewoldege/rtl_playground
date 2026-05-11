`timescale 1ns/1ps
module processing_element
#(
    parameter int ACCUM_W = 32,
    parameter int WEIGHT_W = 8,
    parameter int ACTIVATION_W = 8,
    parameter int MULT_W = WEIGHT_W + ACTIVATION_W
)
(
    input clk,
    input rst_n,

    input logic weight_load_in,
    input logic [WEIGHT_W-1:0] weight_in,

    // It is assumed that when the activation is valid,
    // the input accumulator is also valid
    // We are putting the owness on the orchestrator to ensure this
    input logic valid_in,
    input logic last_in,
    input logic [ACTIVATION_W-1:0] activation_in,
    input logic [ACCUM_W-1:0]      accum_in,

    output logic valid_out,
    output logic last_out,
    output logic [ACTIVATION_W-1:0] activation_out,
    output logic [ACCUM_W-1:0]      accum_out
);

logic [WEIGHT_W-1:0] weight_val;
logic [PROCESSING_ELEMENT_LATENCY-1:0][ACTIVATION_W-1:0] activation_sreg;
logic [PROCESSING_ELEMENT_LATENCY-1:0][ACCUM_W-1:0] accum_sreg;
logic [PROCESSING_ELEMENT_LATENCY-1:0] valid_sreg;
logic [PROCESSING_ELEMENT_LATENCY-1:0] last_sreg;

logic signed [ACTIVATION_W-1:0] activation_signed;
logic signed [WEIGHT_W-1:0] weight_signed;
logic signed [MULT_W-1:0] mult;
logic signed [MULT_W-1:0] mult_q;
logic signed [ACCUM_W-1:0] mult_ext;
logic signed [ACCUM_W-1:0] accum_reg_q;
logic signed [ACCUM_W-1:0] accum_temp;
logic signed [ACCUM_W-1:0] accum_sat;
logic accum_overflow;

initial begin
    if (PROCESSING_ELEMENT_LATENCY < 2) begin
        $fatal(1, "PROCESSING_ELEMENT_LATENCY must be at least 2 for the registered multiply/add PE");
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        weight_val <= '0;
        mult_q <= '0;
        accum_reg_q <= '0;
        valid_sreg <= '0;
        last_sreg <= '0;
        accum_sreg <= '0;
        activation_sreg <= '0;
    end else begin
        if(weight_load_in)
            weight_val <= weight_in;

        valid_sreg[0] <= valid_in;
        last_sreg[0] <= last_in && valid_in;
        if (valid_in) begin
            activation_sreg[0] <= activation_in;
            mult_q <= mult;
            accum_reg_q <= $signed(accum_in);
        end

        for (int i = 1; i < PROCESSING_ELEMENT_LATENCY; i++) begin
            valid_sreg[i] <= valid_sreg[i-1];
            last_sreg[i]  <= last_sreg[i-1];
        end

        if (valid_sreg[0]) begin
            activation_sreg[1] <= activation_sreg[0];
            accum_sreg[1] <= accum_overflow ? accum_sat : accum_temp;
        end

        for (int i = 2; i < PROCESSING_ELEMENT_LATENCY; i++) begin
            if (valid_sreg[i-1]) begin
                activation_sreg[i] <= activation_sreg[i-1];
                accum_sreg[i] <= accum_sreg[i-1];
            end
        end
    end
end

assign activation_signed = activation_in;
assign weight_signed = weight_val;
assign mult = activation_signed * weight_signed;
assign mult_ext = {{(ACCUM_W-MULT_W){mult_q[MULT_W-1]}}, mult_q};
assign accum_temp = mult_ext + accum_reg_q;
assign accum_overflow = (mult_ext[ACCUM_W-1] == accum_reg_q[ACCUM_W-1]) && (accum_temp[ACCUM_W-1] != mult_ext[ACCUM_W-1]);
assign accum_sat = {accum_reg_q[ACCUM_W-1], {(ACCUM_W-1){~accum_reg_q[ACCUM_W-1]}}};

assign activation_out = activation_sreg[PROCESSING_ELEMENT_LATENCY-1];
assign accum_out = accum_sreg[PROCESSING_ELEMENT_LATENCY-1];
assign valid_out = valid_sreg[PROCESSING_ELEMENT_LATENCY-1];
assign last_out  = last_sreg[PROCESSING_ELEMENT_LATENCY-1];

endmodule
