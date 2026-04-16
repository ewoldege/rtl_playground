`timescale 1ns/1ps
import systolic_array_pkg::*;

module systolic_array_cell
#(
    parameter int ACCUM_W = 32,
    parameter int WEIGHT_W = 8,
    parameter int ACTIVATION_W = 8,
    parameter int ARRAY_W = 4
)
(
    input clk,
    input rst_n,

    // Simulataneous weight load of all elements in systolic array
    input logic weight_load_in,
    input logic [ARRAY_W-1:0][ARRAY_W-1:0][WEIGHT_W-1:0] weight_in,

    // It is assumed that when the activation is valid,
    // the input accumulator is also valid
    // We are putting the owness on the orchestrator to ensure this
    input logic valid_in,
    input logic [ARRAY_W-1:0][ACTIVATION_W-1:0] activation_in,

    output logic [ARRAY_W-1:0] valid_out,
    output logic [ARRAY_W-1:0][ACCUM_W-1:0] accum_out
);

localparam int INPUT_PIPE_DEPTH = (ARRAY_W > 1) ? (ARRAY_W - 1) * PROCESSING_ELEMENT_LATENCY : 1;

logic [INPUT_PIPE_DEPTH-1:0][ARRAY_W-1:0][ACTIVATION_W-1:0] activation_pipeline;
logic [INPUT_PIPE_DEPTH-1:0] valid_pipeline;

logic [ARRAY_W-1:0][ARRAY_W-1:0][ACCUM_W-1:0] accum_out_array;
logic [ARRAY_W-1:0][ARRAY_W-1:0][ACTIVATION_W-1:0] activation_out_array;
logic [ARRAY_W-1:0][ARRAY_W-1:0] valid_out_array;

for (genvar i = 0; i < ARRAY_W; i++) begin : row
    for (genvar j = 0; j < ARRAY_W; j++) begin : col
        logic pe_valid_in;
        logic [ACTIVATION_W-1:0] pe_activation_in;
        logic [ACCUM_W-1:0] pe_accum_in;

        if (i == 0) begin : first_row
            assign pe_valid_in = valid_in;
            assign pe_activation_in = activation_in[i];
            assign pe_accum_in = '0;
        end else begin : later_rows
            assign pe_valid_in = valid_pipeline[i*PROCESSING_ELEMENT_LATENCY-1];
            assign pe_activation_in = activation_pipeline[i*PROCESSING_ELEMENT_LATENCY-1][i];
            assign pe_accum_in = accum_out_array[i-1][j];
        end

        processing_element #(
            .ACCUM_W(ACCUM_W),
            .WEIGHT_W(WEIGHT_W),
            .ACTIVATION_W(ACTIVATION_W)
        ) pe (
            .clk(clk),
            .rst_n(rst_n),
            .weight_load_in(weight_load_in),
            .weight_in(weight_in[i][j]),
            .valid_in(pe_valid_in),
            .activation_in(pe_activation_in),
            .accum_in(pe_accum_in),
            .valid_out(valid_out_array[i][j]),
            .activation_out(activation_out_array[i][j]),
            .accum_out(accum_out_array[i][j])
        );
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        valid_pipeline <= '0;
        activation_pipeline <= '0;
    end else begin
        valid_pipeline[0] <= valid_in;
        activation_pipeline[0] <= activation_in;

        for(int i = 1; i < INPUT_PIPE_DEPTH; i++) begin
            valid_pipeline[i] <= valid_pipeline[i-1];
            activation_pipeline[i] <= activation_pipeline[i-1];
        end
    end
end

assign valid_out = valid_out_array[ARRAY_W-1][ARRAY_W-1:0];
assign accum_out = accum_out_array[ARRAY_W-1][ARRAY_W-1:0];

endmodule
