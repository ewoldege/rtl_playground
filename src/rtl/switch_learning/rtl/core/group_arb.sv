module group_arb 
#(
    parameter TC_NUM = 4;
    parameter PORT_PER_GROUP = 4;
    parameter TC_NUM_W = clog2(TC_NUM);
    parameter PORT_PER_GROUP_W = clog2(PORT_PER_GROUP)
)
(
    input clk;
    input rst_n;

    input choose_next_i;

    // There are 4 FIFO interface per ports
    // There are 4 ports per group
    // There is one metadata entry per packet, thus this will tell us if we have any packets
    input [PORT_PER_GROUP-1:0][PORT_PER_GROUP-1:0] fifo_pkt_meta_empty;
    output [PORT_PER_GROUP-1:0][PORT_PER_GROUP-1:0] fifo_grant;
    output grant_valid_o;

    output ready_o
);

    typedef enum logic[2:0]{
        ST_IDLE = 2'd0,
        ST_SEL_TC_PER_PORT = 2'd1,
        ST_FIND_MAX_TC = 2'd2,
        ST_IDENTIFY_WHICH_TO_ARB = 2'd3
        ST_ARB = 2'd4
    } state_t;

    state_t curr_state, next_state;
    integer i,j,k;
    logic[PORT_PER_GROUP-1:0][TC_NUM_W-1:0] chosen_tc_per_port, chosen_tc_per_port_q;
    logic[TC_NUM_W-1:0] max_tc, max_tc_q; // Chosen TC for abitration
    logic[PORT_PER_GROUP-1:0] arb_bus, arb_bus_q; // Bus indicating which ports in the port group = MAX_TC
    logic enable_arb;


    always_ff @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            curr_state <= IDLE;
        end else begin
            curr_state <= next_state;
            chosen_tc_per_port_q <= chosen_tc_per_port;
            max_tc_q <= max_tc;
            arb_bus_q <= arb_bus;
        end
    end

    always_comb begin
        next_state = curr_state;
        max_tc = max_tc_q;
        arb_bus = arb_bus_q;
        chosen_tc_per_port = chosen_tc_per_port_q;
        case (curr_state)
            IDLE: begin
                if(choose_next_i && ready_o)
                    next_state <= ST_SEL_TC_PER_PORT;
            end
            ST_SEL_TC_PER_PORT: begin
                // Priority encoder to find the max TC in each port
                next_state <= ST_FIND_MAX_TC;
                chosen_tc_per_port = '0;
                for(i=0;i<PORT_PER_GROUP;i++) begin
                    for(j=0;j<TC_NUM;j++) begin
                        if(~fifo_pkt_meta_empty[i][j]) begin
                            chosen_tc_per_port[i] = j;
                        end
                    end 
                end
            end
            ST_FIND_MAX_TC: begin
                // Comparator tree to find max TC in the port group
                next_state <= ST_IDENTIFY_WHICH_TO_ARB;
                max_tc = '0;
                for(k=0;k<PORT_PER_GROUP;k++) begin
                    if(chosen_tc_per_port[k] > max_tc) begin
                        max_tc = chosen_tc_per_port[k]
                    end
                end
            end
            ST_IDENTIFY_WHICH_TO_ARB: begin
                next_state <= ST_ARB;
                // Indicate which ports in the group contain the max TC
                arb_bus <= '0;
                for(k=0;k<PORT_PER_GROUP;k++) begin
                    if(chosen_tc_per_port[k] == max_tc) begin
                        arb_bus[k] = 1'b1;
                    end
                end
            end
            ST_ARB: begin
                next_state <= IDLE;
                enable_arb <= 1'b1;
            end
        endcase
    end

    u_rr_arb rr_arb (
        .clk(clk),
        .rst_n(rst_n),
        .sel_next_i(enable_arb)
        .upstream_ready_i(arb_bus_q),
        .upstream_grant_o(arb_result),
        .downstream_ready_i(enable_arb)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            grant_valid <= 1'b0;
        end else begin
            grant_valid <= enable_arb;
            if(enable_arb) begin
                fifo_grant[arb_result][max_tc] <= 1'b1;
            end
        end
    end

    assign ready = (curr_state == IDLE) ? 1'b1 : 1'b0;

endmodule;