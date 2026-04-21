`timescale 1ns/1ps
import systolic_array_pkg::*;

module systolic_array_top
#(
    parameter int ACCUM_W = 32,
    parameter int WEIGHT_W = 8,
    parameter int ACTIVATION_W = 8,
    parameter int ARRAY_W = 4,
    parameter int MAT_W = 16,
    parameter int ARRAY_W_W = $clog2(ARRAY_W),
    parameter int MAT_W_W = $clog2(MAT_W)
)
(
    input clk,
    input rst_n,

    input inst_load,
    input instr_t instr_in,

    // Simulataneous weight load of all elements in systolic array
    output logic weight_rd_en_out,
    output logic [MAT_W_W-1:0] weight_rd_addr_out,
    input logic [MAT_W-1:0][WEIGHT_W-1:0] weight_in,

    // It is assumed that when the activation is valid,
    // the input accumulator is also valid
    // We are putting the owness on the orchestrator to ensure this
    output logic act_rd_en_out,
    output logic [MAT_W_W-1:0] act_rd_addr_out,
    input logic [MAT_W-1:0][ACTIVATION_W-1:0] activation_in,

    output logic valid_out,
    input  logic ready_in,
    output logic [ARRAY_W-1:0][ACCUM_W-1:0] accum_out
);

localparam int INPUT_PIPE_DEPTH = (ARRAY_W > 1) ? (ARRAY_W - 1) * PROCESSING_ELEMENT_LATENCY : 1;

// Technically, we are draining the output FIFOs after all inputs hvae been processed and written into the FIFOs
// this i a function of (ARRAY_W - 1) * PROCESSING_ELEMENT_LATENCY. But thats the time the last wren hits the rightmost FIFO
// we are using the empty signal to determine when we can read, so thats an extra 2 cycles of latency
// There are other cycles of latency we may be missing, so to cover those we are adding some fixed margin for now.
localparam int FIFO_DEPTH        = 2*INPUT_PIPE_DEPTH + 16;
localparam int FIFO_WIDTH        = ACCUM_W;
localparam int FIFO_AFULL_THRESH = FIFO_DEPTH - (INPUT_PIPE_DEPTH + 8);

logic [INPUT_PIPE_DEPTH-1:0][ARRAY_W-1:0][ACTIVATION_W-1:0] activation_pipeline;
logic [INPUT_PIPE_DEPTH-1:0] valid_pipeline;

logic [ARRAY_W-1:0][ARRAY_W-1:0][ACCUM_W-1:0] accum_out_array;
logic [ARRAY_W-1:0][ARRAY_W-1:0][ACTIVATION_W-1:0] activation_out_array;
logic [ARRAY_W-1:0][ARRAY_W-1:0] valid_out_array;

logic [ARRAY_W-1:0] accum_stage_buffer_empty;
logic accum_stage_buffer_rden;
logic [ARRAY_W-1:0][ACCUM_W-1:0] accum_stage_buffer_rdata;

typedef enum {IDLE, FETCH_VEC, ACT_FETCH_VEC, WEIGHT_LOAD, SERVICE, RESET_ACCUM, DRAIN} state_t;
state_t curr_state, next_state;
instr_t instr;
logic [ARRAY_W_W-1:0] fetch_en_cnt;
logic [ARRAY_W_W-1:0] act_fetch_en_cnt;
logic clear_array_stats;
logic weight_load;
logic weight_val;
logic act_valid;
logic act_load;
logic col_end;
logic tile_end;
logic accum_clr;
logic accum_clr_q;
logic [ARRAY_W-1:0][MAT_W-1:0][ACTIVATION_W-1:0] act_sreg;
logic [ARRAY_W-1:0][MAT_W-1:0][WEIGHT_W-1:0] weight_sreg;
logic [MAT_W_W-1:0] weight_load_cnt;
logic [MAT_W_W-1:0] service_cnt;
logic [MAX_TILES_W-1:0] tile_end_cnt;
logic [MAX_TILES_W-1:0] col_end_cnt;

logic sys_valid;
logic sys_last;
logic [ARRAY_W-1:0][ACCUM_W-1:0] sys_accum;
logic [MAT_W_W-1:0] inc_addr;

logic banked_accum_ready;
logic drain_active;
logic [MAT_W_W-1:0] drain_addr;

logic [ARRAY_W-1:0][ACTIVATION_W-1:0] activation;
logic [ARRAY_W-1:0][WEIGHT_W-1:0] weight;

always_comb begin
    weight_rd_en_out = 1'b0;
    clear_array_stats = 1'b0;
    act_rd_en_out = 1'b0;
    col_end = 1'b0;
    weight_load = 1'b0;
    next_state = curr_state;
    accum_clr = 1'b0;
    act_valid = 1'b0;
    case(curr_state)
        IDLE: begin
            clear_array_stats = 1'b1;
            if(inst_load) begin
               next_state = FETCH_VEC; 
            end
        end
        FETCH_VEC: begin
            weight_rd_en_out = 1'b1;
            act_rd_en_out = 1'b1;
            if(fetch_en_cnt == ARRAY_W-1)
                next_state = WEIGHT_LOAD;
        end
        ACT_FETCH_VEC: begin
            act_rd_en_out = 1'b1;
            if(act_fetch_en_cnt == ARRAY_W-1)
                next_state = WEIGHT_LOAD;
        end
        WEIGHT_LOAD: begin
            weight_load = 1'b1;
            if(weight_load_cnt == ARRAY_W-1)
                next_state = SERVICE;
        end
        SERVICE: begin
            act_valid = 1'b1;
            // Passed all activations for a given tile
            if(service_cnt == MAT_W-1) begin 
                tile_end = 1'b1;
                // If we've reached the last tile in the column, we need to notify the accumulators
                // to latch the final values and fetch new weights AND activations from the external SRAM
                // If we have not, then we need to just fetch new activations for the next tile in the columnn.
                if(tile_end_cnt == instr.num_tiles-1) begin
                    accum_clr = 1'b1;
                    next_state = RESET_ACCUM;                    
                end else
                    next_state = ACT_FETCH_VEC;                
            end
        end
        RESET_ACCUM: begin
            // Let accumulator clear for one cycle (accum_clr is registered)
            next_state = DRAIN;
        end
        DRAIN: begin
            col_end = 1'b1;
            // If we've reached the maximum number of horizontal tiles - we are finished.
            if(col_end_cnt == instr.num_tiles-1) begin
                next_state = IDLE;
            end else begin
                next_state = FETCH_VEC;
            end
        end
    endcase
end

always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        curr_state <= IDLE;
        service_cnt <= '0;
        fetch_en_cnt <= '0;
        act_fetch_en_cnt <= '0;
        weight_load_cnt <= '0;
        act_load <= '0;
        tile_end_cnt <= '0;
        instr <= '0;
        inc_addr <= '0;
        drain_active <= 1'b0;
        drain_addr <= '0;
        accum_clr_q <= 1'b0;
        weight_val <= 1'b0;
        act_rd_addr_out <= '0;
        col_end_cnt <= '0;
    end else begin
        curr_state <= next_state;
        weight_val <= weight_rd_en_out;
        act_load <= act_rd_en_out;
        accum_clr_q <= accum_clr;
        if(inst_load && (curr_state == FETCH_VEC))
            instr <= instr_in;
        if(curr_state == FETCH_VEC) begin
            fetch_en_cnt <= fetch_en_cnt + 1;
        end else begin
            fetch_en_cnt <= '0;
        end
        if(curr_state == ACT_FETCH_VEC) begin
            act_fetch_en_cnt <= act_fetch_en_cnt + 1;
        end else begin
            act_fetch_en_cnt <= '0;
        end
        if(curr_state == WEIGHT_LOAD) begin
            weight_load_cnt <= weight_load_cnt + 1;
        end else begin
            weight_load_cnt <= '0;
        end
        if(act_load) begin
            act_sreg <= {act_sreg[ARRAY_W-2:0], activation_in};
        end else if(act_valid) begin
            for(int i = 0; i < ARRAY_W; i++) begin
                act_sreg[i] <= {act_sreg[i][MAT_W-2:0], '0};
            end
        end
        if(weight_val) begin
            weight_sreg <= {weight_sreg[ARRAY_W-2:0], weight_in};
        end else if(weight_load) begin
            for(int i = 0; i < ARRAY_W; i++) begin
                weight_sreg[i] <= {weight_sreg[i][MAT_W-2:0], '0};
            end
        end

        if(act_valid) begin
            service_cnt <= service_cnt + 1;
        end else begin
            service_cnt <= '0;
        end
        if (clear_array_stats)
            act_rd_addr_out <= '0;
        else if (act_rd_en_out)
            act_rd_addr_out <= act_rd_addr_out + 1;
        if (clear_array_stats || col_end)
            tile_end_cnt <= '0;
        else if (tile_end)
            tile_end_cnt <= tile_end_cnt + 1;

        if(clear_array_stats || sys_last)
            inc_addr <= '0;
        else if(sys_valid)
            inc_addr <= inc_addr + 1;

        if(clear_array_stats)
            col_end_cnt <= '0;
        else if(col_end)
            col_end_cnt <= col_end_cnt + 1;

        // Drain sequence
        // When we reach the end of a tile column, we drain the results of the banked accumulators
        
        // TODO CHECK TO SEE IF WE STILL NEED TO RESET THE BANKED ACCUMULATOR AFTER COL_END
        // IF WE DO THEN WE MAY NEED TO ADJUST THE TIMING OF THIS
        if(col_end) begin
            drain_active <= 1'b1;
            drain_addr <= '0;
        end else if(drain_active && (drain_addr == MAT_W-1)) begin
            drain_addr <= '0;
            drain_active <= 1'b0;
        end else if(drain_active) begin
            drain_addr <= drain_addr + 1;
        end


    end
end

always_comb begin
    for(int i = 0; i < ARRAY_W; i++) begin
        activation[i] = act_sreg[i][0];
        weight[i] = weight_sreg[i][0];
    end
end

systolic_array_cell #(
    .ACCUM_W(ACCUM_W),
    .WEIGHT_W(WEIGHT_W),
    .ACTIVATION_W(ACTIVATION_W),
    .ARRAY_W(ARRAY_W)
) systolic_array (
    .clk(clk),
    .rst_n(rst_n),
    .weight_clr_in(clear_array_stats),
    .weight_load_in(weight_load),
    .weight_in(weight),
    .valid_in(act_valid),
    .last_in(tile_end),
    .activation_in(activation),
    .valid_out(sys_valid),
    .last_out(sys_last),
    .ready_in(banked_accum_ready),
    .accum_out(sys_accum)
);

assign banked_accum_ready = 1'b1;

banked_accum #(
    .ACCUM_W(ACCUM_W),
    .ARRAY_W(ARRAY_W),
    .MAT_W(MAT_W)
) u_banked_accum (
    .clk(clk),
    .rst_n(rst_n),
    .clr(accum_clr_q),
    .inc_valid(sys_valid),
    .inc_addr(inc_addr),
    .inc_data(sys_accum),
    .rd_en(drain_active),
    .rd_addr(drain_addr),
    .rd_data(accum_out)
);

endmodule
