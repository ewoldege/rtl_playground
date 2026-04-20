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
    input logic weight_clr_in,
    input logic weight_load_in,
    input logic [ARRAY_W-1:0][WEIGHT_W-1:0] weight_in,

    // It is assumed that when the activation is valid,
    // the input accumulator is also valid
    // We are putting the owness on the orchestrator to ensure this
    input logic valid_in,
    input logic last_in,
    input logic [ARRAY_W-1:0][ACTIVATION_W-1:0] activation_in,

    output logic valid_out,
    output logic last_out,
    input  logic ready_in,
    output logic [ARRAY_W-1:0][ACCUM_W-1:0] accum_out
);

localparam int INPUT_PIPE_DEPTH = (ARRAY_W > 1) ? (ARRAY_W - 1) * PROCESSING_ELEMENT_LATENCY : 1;
localparam int ARRAY_W_W = $clog2(ARRAY_W);

// Technically, we are draining the output FIFOs after all inputs hvae been processed and written into the FIFOs
// this i a function of (ARRAY_W - 1) * PROCESSING_ELEMENT_LATENCY. But thats the time the last wren hits the rightmost FIFO
// we are using the empty signal to determine when we can read, so thats an extra 2 cycles of latency
// There are other cycles of latency we may be missing, so to cover those we are adding some fixed margin for now.
localparam int FIFO_DEPTH        = 2*INPUT_PIPE_DEPTH + 16;
localparam int FIFO_WIDTH        = ACCUM_W;
localparam int FIFO_AFULL_THRESH = FIFO_DEPTH - (INPUT_PIPE_DEPTH + 8);

logic [INPUT_PIPE_DEPTH-1:0][ARRAY_W-1:0][ACTIVATION_W-1:0] activation_pipeline;
logic [INPUT_PIPE_DEPTH-1:0] valid_pipeline;
logic [INPUT_PIPE_DEPTH-1:0] last_pipeline;

logic [ARRAY_W-1:0][ARRAY_W-1:0][ACCUM_W-1:0] accum_out_array;
logic [ARRAY_W-1:0][ARRAY_W-1:0][ACTIVATION_W-1:0] activation_out_array;
logic [ARRAY_W-1:0][ARRAY_W-1:0] valid_out_array;
logic [ARRAY_W-1:0][ARRAY_W-1:0] last_out_array;

logic [ARRAY_W-1:0] accum_stage_buffer_empty;
logic accum_stage_buffer_rden;
logic [ARRAY_W-1:0][FIFO_WIDTH:0] accum_stage_buffer_rdata;

logic [ARRAY_W-1:0] weight_load;
logic [ARRAY_W_W-1:0] weight_load_index;


always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        weight_load_index <= '0;
    end else begin
        if(weight_clr_in)
            weight_load_index <= '0;
        else if(weight_load_in)
            weight_load_index <= weight_load_index + 1;
    end
end
assign weight_load = weight_load_in << weight_load_index;

for (genvar i = 0; i < ARRAY_W; i++) begin : row
    for (genvar j = 0; j < ARRAY_W; j++) begin : col
        logic pe_valid_in;
        logic pe_last_in;
        logic [ACTIVATION_W-1:0] pe_activation_in;
        logic [ACCUM_W-1:0] pe_accum_in;
        

        if (i == 0) begin : first_row
            assign pe_valid_in = valid_in;
            assign pe_last_in = last_in;
            assign pe_activation_in = activation_in[i];
            assign pe_accum_in = '0;
        end else begin : later_rows
            assign pe_valid_in = valid_pipeline[i*PROCESSING_ELEMENT_LATENCY-1];
            assign pe_last_in = last_pipeline[i*PROCESSING_ELEMENT_LATENCY-1];
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
            .weight_load_in(weight_load[i]),
            .weight_in(weight_in[j]),
            .valid_in(pe_valid_in),
            .last_in(pe_last_in),
            .activation_in(pe_activation_in),
            .accum_in(pe_accum_in),
            .valid_out(valid_out_array[i][j]),
            .last_out(last_out_array[i][j]),
            .activation_out(activation_out_array[i][j]),
            .accum_out(accum_out_array[i][j])
        );
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        valid_pipeline <= '0;
        last_pipeline <= '0;
        activation_pipeline <= '0;
    end else begin
        valid_pipeline[0] <= valid_in;
        last_pipeline[0] <= last_in;
        activation_pipeline[0] <= activation_in;

        for(int i = 1; i < INPUT_PIPE_DEPTH; i++) begin
            valid_pipeline[i] <= valid_pipeline[i-1];
            last_pipeline[i] <= last_pipeline[i-1];
            activation_pipeline[i] <= activation_pipeline[i-1];
        end
    end
end

// TODO: Add backpressure capabilities to this design by connecting the afull signals
// threshold has already been computed above
for(genvar j = 0; j < ARRAY_W; j++) begin
    fifo_fwft_sync #(
        .DATA_W(FIFO_WIDTH+1),
        .DEPTH(FIFO_DEPTH)
    )
    accum_stage_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(valid_out_array[ARRAY_W-1][j]),
        .wr_data({last_out_array[ARRAY_W-1][j], accum_out_array[ARRAY_W-1][j]}),
        .full(),
        .rd_en(accum_stage_buffer_rden),
        .rd_data(accum_stage_buffer_rdata[j]),
        .empty(accum_stage_buffer_empty[j])
    );

    assign accum_out[j] = accum_stage_buffer_rdata[j][FIFO_WIDTH-1:0];
end

// Read only when all buffers are nonempty and downstream is ready
assign accum_stage_buffer_rden = &(~accum_stage_buffer_empty) & ready_in;
assign valid_out = &(~accum_stage_buffer_empty);
assign last_out = accum_stage_buffer_rdata[0][FIFO_WIDTH];

always_ff @(posedge clk) begin
    if (rst_n && valid_out) begin
        for (int i = 1; i < ARRAY_W; i++) begin
            assert (accum_stage_buffer_rdata[i][FIFO_WIDTH] == accum_stage_buffer_rdata[0][FIFO_WIDTH])
                else $error("accum_stage_buffer_rdata MSB mismatch: lane 0=%0b lane %0d=%0b",
                            accum_stage_buffer_rdata[0][FIFO_WIDTH],
                            i,
                            accum_stage_buffer_rdata[i][FIFO_WIDTH]);
        end
    end
end

endmodule
