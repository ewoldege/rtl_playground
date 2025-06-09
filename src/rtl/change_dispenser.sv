module adder(

    input clk,
    input rst,

    // Input interface
    input [6:0] paid_cmt_i,
    input valid_i;

    // Output Interface
    output quarter_disp_o,
    output dime_disp_o,
    output nickel_disp_o,
    output penny_disp_o,

    output ready_o
);

logic rem_gt_25, rem_gt_10, rem_gt_5, rem_gt_1;
logic input_handshake;
logic ready;
logic [6:0] remaining_balance, remaining_balance_q;
typedef enum {IDLE, QUARTER, DIME, NICKEL, PENNY} state_t;
state_t curr_state, next_state;

assign input_handshake = ready_o & valid_i;
assign rem_gt_25 = remaining_balance_q >= 25;
assign rem_gt_10 = remaining_balance_q >= 10;
assign rem_gt_5 = remaining_balance_q >= 5;
assign rem_gt_1 = remaining_balance_q >= 1;

always_ff @(posedge clk) begin
    if(rst) begin
        curr_state <= IDLE;
        remaining_balance_q <= '0;
    end else begin 
        curr_state <= next_state;
        remaining_balance_q <= remaining_balance;
    end
end

always_comb begin
  case (curr_state)
    IDLE: begin // Ready to accept new data. Output data is invalid in this state
      ready = 1'b1;
      if(input_handshake) begin
        remaining_balance = paid_cmt_i;
        if 
        next_state = DECISION;
      end else begin
        remaining_balance = '0;
        next_state = IDLE;
      end
    end
    DECISION: begin // Processing data, do not accept new data. Output processed data
      if (rem_gt_25)
    end
    endcase 
end

assign ready_o = ready;

endmodule
