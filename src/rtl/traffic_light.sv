module traffic_light 
#(
    parameter int GREEN_CYCLE_LENGTH = 10,
    parameter int YELLOW_CYCLE_LENGTH = 3
)
(
    input clk,
    input rst_n,

    output ns_g_o,
    output ns_y_o,
    output ns_r_o,
    output ew_g_o,
    output ew_y_o,
    output ew_r_o
);
typedef enum {NS_GREEN, NS_YELLOW, EW_GREEN, EW_YELLOW} state_t;
state_t curr_state, next_state;

logic [31:0] cnt_next, cnt;

logic ns_g;
logic ns_y;
logic ns_r;
logic ew_g;
logic ew_y;
logic ew_r;

always_ff @(posedge clk) begin
    if(~rst_n) begin
        curr_state <= NS_GREEN;
        cnt <= '0;
    end else begin 
        curr_state <= next_state;
        cnt <= cnt_next;
    end
end

always_comb begin
  case (curr_state)
    NS_GREEN: begin
        if (cnt == GREEN_CYCLE_LENGTH-1) begin
            cnt_next = 0;
            next_state = NS_YELLOW;
        end else begin
            cnt_next = cnt + 1;
            next_state = NS_GREEN;
        end
        ns_g = 1'b1;
        ns_y = 1'b0;
        ns_r = 1'b0;
        ew_g = 1'b0;
        ew_y = 1'b0;
        ew_r = 1'b1;
    end
        
    NS_YELLOW: begin
        if (cnt == YELLOW_CYCLE_LENGTH-1) begin
            cnt_next = 0;
            next_state = EW_GREEN;
        end else begin
            cnt_next = cnt + 1;
            next_state = NS_YELLOW;
        end
        ns_g = 1'b0;
        ns_y = 1'b1;
        ns_r = 1'b0;
        ew_g = 1'b0;
        ew_y = 1'b0;
        ew_r = 1'b1;
    end
    EW_GREEN: begin
        if (cnt == GREEN_CYCLE_LENGTH-1) begin
            cnt_next = 0;
            next_state = EW_YELLOW;
        end else begin
            cnt_next = cnt + 1;
            next_state = EW_GREEN;
        end
        ns_g = 1'b0;
        ns_y = 1'b0;
        ns_r = 1'b1;
        ew_g = 1'b1;
        ew_y = 1'b0;
        ew_r = 1'b0;
    end
    EW_YELLOW: begin
        if (cnt == YELLOW_CYCLE_LENGTH-1) begin
            cnt_next = 0;
            next_state = NS_GREEN;
        end else begin
            cnt_next = cnt + 1;
            next_state = EW_YELLOW;
        end
        ns_g = 1'b0;
        ns_y = 1'b0;
        ns_r = 1'b1;
        ew_g = 1'b0;
        ew_y = 1'b1;
        ew_r = 1'b0;
    end
    endcase 
end

assign ns_g_o = ns_g;
assign ns_y_o = ns_y;
assign ns_r_o = ns_r;
assign ew_g_o = ew_g;
assign ew_y_o = ew_y;
assign ew_r_o = ew_r;

endmodule