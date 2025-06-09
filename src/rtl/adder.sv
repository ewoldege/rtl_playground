module adder(

    input clk,
    input rst,

    // Input interface
    input i_req, // Input valid
    input [31:0] i_data, // Data A
    input [31:0] i_datb, // Data B
    output i_ack, // Request for new data from upstream

    // Output interface
    output  o_req, // Output valid
    output [31:0] o_datc, // Output Data C
    input   o_ack  // Handshake ready 
);
logic [31:0] c, c_q;
logic downstream_handshake_complete;
logic upstream_handshake_complete;
logic upstream_ack;
logic downstream_ready;

typedef enum {IDLE, DATA} state_t;
state_t curr_state, next_state;

assign downstream_handshake_complete = o_ack & o_req; // Downstream output handshake is complete when these two are asserted
assign upstream_handshake_complete = i_ack & i_req; // Upstream output handshake is complete when these two are asserted

always_comb begin
    // Assumes no overflow. If we need to account for overflow, resize c to 33-bits to account for overflow bit
    c   = upstream_handshake_complete ? (i_data + i_datb) : c_q; // Add A+B when input data is valid, else hold the value
end

always_ff @(posedge clk) begin
    if(rst) begin
        c_q <= '0;
        curr_state <= IDLE;
    end else begin
        c_q <= c;    
        curr_state <= next_state;
    end
end

always_comb begin
  case (curr_state)
    IDLE: begin // Ready to accept new data. Output data is invalid in this state
      upstream_ack = 1;
      downstream_ready = 0;
      if(upstream_handshake_complete) // Exit once upstream block sends new data
        next_state = DATA;
      else
        next_state = IDLE;
    end
    DATA: begin // Processing data, do not accept new data. Output processed data
      upstream_ack = 0;
      downstream_ready = 1;
      if(downstream_handshake_complete) // Exit once downstream block accepts data
        next_state = IDLE;
      else
        next_state = DATA;
    end
    endcase 
end
  
assign o_datc = c_q;
assign i_ack = upstream_ack;
assign o_req = downstream_ready;
endmodule
