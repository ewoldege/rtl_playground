module rr_arbiter 
#(
    parameter NUM_REQUESTORS = 16
)
(
    input clk,
    input rst_n,

    input logic [NUM_REQUESTORS-1:0] req_i,
    input logic valid_i,
    input logic [63:0] data_i,
    input logic tlast_i;
    output logic valid_o,
    output logic [63:0] data_o
);

typedef enum {IDLE, S0, S1, S2, S3} state_t;
state_t curr_state, next_state;

logic active;
logic [$clog2(NUM_REQUESTORS)-1:0] grant;

always_ff @(posedge clk) begin
    if(rst) begin
        curr_state <= IDLE;
    end else begin 
        curr_state <= next_state;
    end
end

always_comb begin
  case (curr_state)
    IDLE: begin // Ready to accept new data. Output data is invalid in this state
        if(req[0])
            next_state = S0;
        else if(req[1])
            next_state = S1;
        else if(req[2])
            next_state = S2;
        else if(req[3])
            next_state = S3;
        active = 0;
        grant = 'd0;
    end
    S0: begin // Processing data, do not accept new data. Output processed data
        if(tlast_i) begin
            if(req[1])
                next_state = S1;
            else if(req[2])
                next_state = S2;
            else if(req[3])
                next_state = S3;
            else if(req[0])
                next_state = S0;
        end else begin
            next_state = S0;
        end
        active = 1;
        grant = 'd0;
    end
    S1: begin // Processing data, do not accept new data. Output processed data
        if(tlast_i) begin
            if(req[2])
                next_state = S2;
            else if(req[3])
                next_state = S3;
            else if(req[0])
                next_state = S0;
            else if(req[1])
                next_state = S1;
        end else begin
            next_state = S1;
        end
        active = 1;
        grant = 'd1;
    end
    S2: begin // Processing data, do not accept new data. Output processed data
        if(tlast_i) begin
            if(req[3])
                next_state = S3;
            else if(req[0])
                next_state = S0;
            else if(req[1])
                next_state = S1;
            else if(req[2])
                next_state = S2;
        end else begin
            next_state = S2;
        end
        active = 1;
        grant = 'd2;
    end
    S3: begin // Ready to accept new data. Output data is invalid in this state
        if(tlast_i) begin
            if(req[0])
                next_state = S0;
            else if(req[1])
                next_state = S1;
            else if(req[2])
                next_state = S2;
            else if(req[3])
                next_state = S3;
        end else begin
            next_state = S3;
        end
        active = 1;
        grant = 'd3;
    end
    endcase 
end

assign get_next_state

endmodule