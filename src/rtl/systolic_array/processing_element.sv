`timescale 1ns/1ps
module processing_element
#(
    parameter int ACCUM_W = 32,
    parameter int WEIGHT_W = 8,
    parameter int ACTIVATION_W = 8
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

always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        weight_val <= '0;
        valid_sreg <= '0;
        last_sreg <= '0;
        accum_sreg <= '0;
        activation_sreg <= '0;
    end else begin
        if(weight_load_in)
            weight_val <= weight_in;
        valid_sreg[0] <= valid_in;
        last_sreg[0] <= last_in && valid_in;
        for (int i = 1; i < PROCESSING_ELEMENT_LATENCY; i++) begin
            valid_sreg[i] <= valid_sreg[i-1];
            last_sreg[i]  <= last_sreg[i-1];
        end

        activation_sreg[0] <= activation_in;
        for (int i = 1; i < PROCESSING_ELEMENT_LATENCY; i++) begin
            activation_sreg[i] <= activation_sreg[i-1];
        end

        // 8x8 multiply = 16 bit; the add still fits inside a 32-bit bus.
        accum_sreg[0] <= activation_in*weight_val + accum_in;
        for (int i = 1; i < PROCESSING_ELEMENT_LATENCY; i++) begin
            accum_sreg[i] <= accum_sreg[i-1];
        end
    end
end

assign activation_out = activation_sreg[PROCESSING_ELEMENT_LATENCY-1];
assign accum_out = accum_sreg[PROCESSING_ELEMENT_LATENCY-1];
assign valid_out = valid_sreg[PROCESSING_ELEMENT_LATENCY-1];
assign last_out  = last_sreg[PROCESSING_ELEMENT_LATENCY-1];

endmodule
