`timescale 1ns/1ps

module group_arb
#(
    parameter int TC_NUM = 4,
    parameter int PORT_PER_GROUP = 4,
    parameter int TC_NUM_W = (TC_NUM > 1) ? $clog2(TC_NUM) : 1,
    parameter int PORT_PER_GROUP_W = (PORT_PER_GROUP > 1) ? $clog2(PORT_PER_GROUP) : 1
)
(
    input  logic                                      clk,
    input  logic                                      rst_n,
    input  logic                                      choose_next_i,
    input  logic [TC_NUM-1:0]                         fifo_pkt_meta_empty [PORT_PER_GROUP-1:0],
    output logic [TC_NUM-1:0]                         fifo_grant [PORT_PER_GROUP-1:0],
    output logic                                      grant_valid_o,
    output logic                                      ready_o
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_SEL_TC_PER_PORT,
        ST_FIND_MAX_TC,
        ST_IDENTIFY_WHICH_TO_ARB,
        ST_ARB
    } state_t;

    state_t curr_state_q, next_state_d;

    logic [TC_NUM_W-1:0] chosen_tc_per_port_d [PORT_PER_GROUP-1:0];
    logic [TC_NUM_W-1:0] chosen_tc_per_port_q [PORT_PER_GROUP-1:0];
    logic [PORT_PER_GROUP-1:0] port_has_pkt_d, port_has_pkt_q;
    logic [TC_NUM_W-1:0] max_tc_d, max_tc_q;
    logic [PORT_PER_GROUP-1:0] arb_bus_d, arb_bus_q;
    logic [PORT_PER_GROUP-1:0] arb_result;
    logic enable_arb;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state_q       <= ST_IDLE;
            for (int i = 0; i < PORT_PER_GROUP; i++) begin
                chosen_tc_per_port_q[i] <= '0;
            end
            port_has_pkt_q     <= '0;
            max_tc_q           <= '0;
            arb_bus_q          <= '0;
        end else begin
            curr_state_q       <= next_state_d;
            for (int i = 0; i < PORT_PER_GROUP; i++) begin
                chosen_tc_per_port_q[i] <= chosen_tc_per_port_d[i];
            end
            port_has_pkt_q     <= port_has_pkt_d;
            max_tc_q           <= max_tc_d;
            arb_bus_q          <= arb_bus_d;
        end
    end

    always_comb begin
        next_state_d         = curr_state_q;
        port_has_pkt_d       = port_has_pkt_q;
        max_tc_d             = max_tc_q;
        arb_bus_d            = arb_bus_q;
        enable_arb           = 1'b0;

        for (int i = 0; i < PORT_PER_GROUP; i++) begin
            chosen_tc_per_port_d[i] = chosen_tc_per_port_q[i];
        end

        case (curr_state_q)
            ST_IDLE: begin
                if (choose_next_i && ready_o) begin
                    next_state_d = ST_SEL_TC_PER_PORT;
                end
            end

            ST_SEL_TC_PER_PORT: begin
                next_state_d         = ST_FIND_MAX_TC;
                port_has_pkt_d       = '0;

                for (int i = 0; i < PORT_PER_GROUP; i++) begin
                    chosen_tc_per_port_d[i] = '0;
                    for (int j = 0; j < TC_NUM; j++) begin
                        if (!fifo_pkt_meta_empty[i][j]) begin
                            chosen_tc_per_port_d[i] = j[TC_NUM_W-1:0];
                            port_has_pkt_d[i]       = 1'b1;
                        end
                    end
                end
            end

            ST_FIND_MAX_TC: begin
                next_state_d = ST_IDENTIFY_WHICH_TO_ARB;
                max_tc_d     = '0;

                for (int k = 0; k < PORT_PER_GROUP; k++) begin
                    if (port_has_pkt_q[k] && (chosen_tc_per_port_q[k] > max_tc_d)) begin
                        max_tc_d = chosen_tc_per_port_q[k];
                    end
                end
            end

            ST_IDENTIFY_WHICH_TO_ARB: begin
                next_state_d = ST_ARB;
                arb_bus_d    = '0;

                for (int k = 0; k < PORT_PER_GROUP; k++) begin
                    if (port_has_pkt_q[k] && (chosen_tc_per_port_q[k] == max_tc_q)) begin
                        arb_bus_d[k] = 1'b1;
                    end
                end
            end

            ST_ARB: begin
                next_state_d = ST_IDLE;
                enable_arb   = |arb_bus_q;
            end

            default: begin
                next_state_d = ST_IDLE;
            end
        endcase
    end

    rr_arb #(
        .NUM_INPUTS(PORT_PER_GROUP)
    ) u_rr_arb (
        .clk(clk),
        .rst_n(rst_n),
        .sel_next_i(enable_arb),
        .upstream_ready_i(arb_bus_q),
        .upstream_grant_o(arb_result),
        .downstream_ready_i(enable_arb)
    );

    always_comb begin
        for (int i = 0; i < PORT_PER_GROUP; i++) begin
            fifo_grant[i] = '0;
        end
        grant_valid_o  = 1'b0;

        if (enable_arb && (|arb_result)) begin
            grant_valid_o = 1'b1;
            for (int i = 0; i < PORT_PER_GROUP; i++) begin
                for (int j = 0; j < TC_NUM; j++) begin
                    if (arb_result[i] && (max_tc_q == j[TC_NUM_W-1:0])) begin
                        fifo_grant[i][j] = 1'b1;
                    end
                end
            end
        end
    end

    assign ready_o = (curr_state_q == ST_IDLE);

endmodule
