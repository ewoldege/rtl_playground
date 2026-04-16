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
    input logic weight_load_in;
    input logic [ARRAY_W-1:0][ARRAY_W-1:0][WEIGHT_W-1:0] weight_in;

    // It is assumed that when the activation is valid,
    // the input accumulator is also valid
    // We are putting the owness on the orchestrator to ensure this
    input logic valid_in,
    input logic [ARRAY_W-1:0][ACTIVATION_W-1:0] activation_in,

    output logic valid_out,
    output logic [ACTIVATION_W-1:0] activation_out,
    output logic accum_valid_out,
    output logic [ACCUM_W-1:0]      accum_out,
);

localparam int MAX_INPUT_DELAY_VAL = (ARRAY_W - 1) * PROCESSING_ELEMENT_LATENCY;

logic [WEIGHT_W-1:0] weight_val;
logic valid_systolic_array;
logic [ARRAY_W-1:0][MAX_INPUT_DELAY_VAL-1:0][ACTIVATION_W-1:0] activation_pipeline;
logic [MAX_INPUT_DELAY_VAL-1:0] valid_pipeline;

logic [ACTIVATION_W-1:0] activation;
logic [ACCUM_W-1:0] accum;
logic [ARRAY_W-1:0][ARRAY_W-1:0][ACCUM_W-1:0] accum_out_array;
logic [ARRAY_W-1:0][ARRAY_W-1:0][ACTIVATION_W-1:0] activation_out_array;
logic [ARRAY_W-1:0][ARRAY_W-1:0] valid_out_array;

for (genvar i = 0; i < ARRAY_W; i++) begin : row
    for (genvar j = 0; j < ARRAY_W; j++) begin : col
        assign accum = (i == 0) ? '0 : accum_out_array[i-1][j];
        assign valid_systolic_array = (j == 0) ? ((i == 0) ? valid_in : valid_pipeline[i*PROCESSING_ELEMENT_LATENCY-1] : valid_out_array[i][j-1]);
        assign activation = (j == 0) ? ((i == 0) ? activation_in : activation_pipeline[i][i*PROCESSING_ELEMENT_LATENCY-1] : activation_out_array[i][j-1]);
        processing_element #(
            .ACCUM_W(ACCUM_W),
            .WEIGHT_W(WEIGHT_W),
            .ACTIVATION_W(ACTIVATION_W)
        ) pe (
            .clk(clk),
            .rst_n(rst_n),
            .weight_load_in(weight_load_in),
            .weight_in(weight_in[i][j]),
            .valid_in(valid_pipeline[i*PROCESSING_ELEMENT_LATENCY-1]),
            .activation_in(activation),
            .accum_in(activation),
            .valid_out(valid_out_array[i][j]),
            .activation_out(activation_out_array[i][j]),
            .accum_out(accum_out_array[i][j])
        );
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        weight_val <= '0;
        valid_out <= '0;
    end else begin
        valid_pipeline[0] <= valid_in;
        valid_pipeline[MAX_INPUT_DELAY_VAL-1:1] <= valid_pipeline[i][MAX_INPUT_DELAY_VAL-2:0];
        for(int i = 0; i < ARRAY_W; i++) begin
            if(valid_in) begin
                activation_pipeline[i][0] <= activation_in[i];
            end
            activation_pipeline[i][MAX_INPUT_DELAY_VAL-1:1] <= activation_pipeline[i][MAX_INPUT_DELAY_VAL-2:0];
        end
    end
end

endmodule