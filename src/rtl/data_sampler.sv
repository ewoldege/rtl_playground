module data_sampler
#(
    parameter DATA_W
)
(
    input fast_clk,
    input slow_clk,
    input rst,

    input logic valid_i,
    input logic[DATA_W-1:0] data_i,

    output  valid_o,
    output logic[DATA_W-1:0] data_o
    
);

logic fast_hold, fast_hold_q, fast_hold_2q;
logic ack, ack_q, ack_2q;
logic[DATA_W-1:0] fast_data_reg, fast_data_hold;

// 1. State Encoding
// Using an enumerated type makes debugging in waveforms much easier
typedef enum logic {
    ST_FAST_IDLE,
    ST_FAST_HOLD
} state_fast_e;
typedef enum logic {
    ST_SLOW_IDLE,
    ST_SLOW_ACK
} state_slow_e;

state_fast_e curr_state_fast, next_state_fast;
state_slow_e curr_state_slow, next_state_slow;

// 2. State Register (Sequential Block)
always_ff @(posedge fast_clk or negedge rst) begin
    if (!rst) begin
        curr_state_fast <= ST_FAST_IDLE;
    end else begin
        curr_state_fast <= next_state_fast;
        ack_q <= ack;
        ack_2q <= ack_q;
        fast_data_reg <= fast_data_hold;
    end
end

// 3. Next State & Output Logic (Combinational Block)
always_comb begin
    // Default values to prevent unintended latches
    next_state_fast = curr_state_fast;

    case (curr_state_fast)
        ST_FAST_IDLE: begin
            if (valid_i) begin
                fast_hold = 1'b1;
                fast_data_hold = data_i;
                next_state_fast = ST_FAST_HOLD;
            end else begin
                fast_hold = 1'b0;
                fast_data_hold = '0;
                next_state_fast = ST_FAST_IDLE;
            end
        end

        ST_FAST_HOLD: begin
            if (ack_2q) begin
                fast_hold = 1'b1;
                fast_data_hold = fast_data_reg;
                next_state_fast = ST_FAST_IDLE;
            end else begin
                fast_hold = 1'b0;
                fast_data_hold = fast_data_reg;
                next_state_fast = ST_FAST_HOLD;
            end
        end
        default: next_state_fast = ST_FAST_IDLE;
    endcase
end

// 2. State Register (Sequential Block)
always_ff @(posedge slow_clk or negedge rst) begin
    if (!rst) begin
        curr_state_slow <= ST_SLOW_IDLE;
    end else begin
        fast_hold_q <= fast_hold;
        fast_hold_2q <= fast_hold_q;
        curr_state_slow <= next_state_slow;
    end
end

// 3. Next State & Output Logic (Combinational Block)
always_comb begin
    // Default values to prevent unintended latches
    next_state_slow = curr_state_slow;

    case (curr_state_slow)
        ST_SLOW_IDLE: begin
            if (fast_hold_2q) begin
                ack = 1'b1;
                next_state_slow = ST_SLOW_ACK;
            end else begin
                ack = 1'b0;
                next_state_slow = ST_SLOW_IDLE;
            end
        end

        ST_SLOW_ACK: begin
            ack = 1'b0;
            next_state_slow = ST_SLOW_IDLE;
        end
        default: next_state_slow = ST_SLOW_IDLE;
    endcase
end

assign valid_o = ack;
assign data_o = fast_data_reg;

endmodule
