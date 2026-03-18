`timescale 1ns/1ps

module tb_group_arb;

    localparam int TC_NUM = 4;
    localparam int PORT_PER_GROUP = 4;

    logic                                  clk;
    logic                                  rst_n;
    logic                                  choose_next_i;
    logic [TC_NUM-1:0] fifo_pkt_meta_empty [PORT_PER_GROUP-1:0];
    logic [TC_NUM-1:0] fifo_grant [PORT_PER_GROUP-1:0];
    logic                                  grant_valid_o;
    logic                                  ready_o;

    group_arb #(
        .TC_NUM(TC_NUM),
        .PORT_PER_GROUP(PORT_PER_GROUP)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .choose_next_i(choose_next_i),
        .fifo_pkt_meta_empty(fifo_pkt_meta_empty),
        .fifo_grant(fifo_grant),
        .grant_valid_o(grant_valid_o),
        .ready_o(ready_o)
    );

    always #5 clk = ~clk;

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            choose_next_i = 1'b0;
            foreach (fifo_pkt_meta_empty[i]) fifo_pkt_meta_empty[i] = '1;
            repeat (2) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    task automatic request_arbitration;
        begin
            wait (ready_o === 1'b1);
            @(negedge clk);
            choose_next_i = 1'b1;
            @(negedge clk);
            choose_next_i = 1'b0;
            wait (grant_valid_o === 1'b1);
            #1;
        end
    endtask

    task automatic launch_request;
        begin
            wait (ready_o === 1'b1);
            @(negedge clk);
            choose_next_i = 1'b1;
            @(negedge clk);
            choose_next_i = 1'b0;
        end
    endtask

    task automatic clear_empty_map;
        begin
            foreach (fifo_pkt_meta_empty[i]) fifo_pkt_meta_empty[i] = '1;
        end
    endtask

    task automatic set_port_tc(
        input int port,
        input int tc
    );
        begin
            fifo_pkt_meta_empty[port][tc] = 1'b0;
        end
    endtask

    task automatic clear_expected_grant;
        begin
            foreach (expected_grant_g[i]) expected_grant_g[i] = '0;
        end
    endtask

    logic [TC_NUM-1:0] expected_grant_g [PORT_PER_GROUP-1:0];

    task automatic expect_grant(input string test_name);
        begin
            for (int i = 0; i < PORT_PER_GROUP; i++) begin
                if (fifo_grant[i] !== expected_grant_g[i]) begin
                    $error("%s failed at port %0d: expected fifo_grant=%b got %b",
                           test_name, i, expected_grant_g[i], fifo_grant[i]);
                    $display("grant_valid_o=%b ready_o=%b state=%0d max_tc_q=%b arb_bus_q=%b arb_result=%b",
                             grant_valid_o, ready_o, dut.curr_state_q, dut.max_tc_q, dut.arb_bus_q, dut.arb_result);
                    $fatal(1);
                end
            end
        end
    endtask

    task automatic expect_no_grant(input string test_name);
        begin
            repeat (6) @(posedge clk);
            if (grant_valid_o !== 1'b0) begin
                $error("%s failed: expected no grant, got grant_valid_o=%b", test_name, grant_valid_o);
                $fatal(1);
            end
            for (int i = 0; i < PORT_PER_GROUP; i++) begin
                if (fifo_grant[i] !== '0) begin
                    $error("%s failed at port %0d: expected fifo_grant=0 got %b",
                           test_name, i, fifo_grant[i]);
                    $fatal(1);
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset_dut();
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_group_arb);

        // Case 1: all FIFOs empty, no grant expected.
        clear_empty_map();
        launch_request();
        expect_no_grant("all_empty");

        reset_dut();

        // Case 2: single non-empty FIFO in the group.
        clear_empty_map();
        set_port_tc(2, 2);

        request_arbitration();
        clear_expected_grant();
        expected_grant_g[2][2] = 1'b1;
        expect_grant("single_fifo");

        reset_dut();

        // Case 3: unique highest TC wins.
        // port0 -> tc1, port1 -> tc3, port2 -> tc1, port3 -> tc2
        clear_empty_map();
        set_port_tc(0, 1);
        set_port_tc(1, 3);
        set_port_tc(2, 1);
        set_port_tc(3, 2);

        request_arbitration();
        clear_expected_grant();
        expected_grant_g[1][3] = 1'b1;
        expect_grant("unique_highest_tc");

        reset_dut();

        // Case 4: one port has multiple non-empty TCs, highest local TC wins.
        // port0 -> tc0/tc2, port1 -> tc1/tc3, port2 -> tc2, port3 -> empty
        clear_empty_map();
        set_port_tc(0, 0);
        set_port_tc(0, 2);
        set_port_tc(1, 1);
        set_port_tc(1, 3);
        set_port_tc(2, 2);

        request_arbitration();
        clear_expected_grant();
        expected_grant_g[1][3] = 1'b1;
        expect_grant("multi_tc_per_port");

        // Case 5: tie on tc3. Since the prior transaction granted port1, the
        // next round-robin choice should start after port1 and pick port3 first.
        clear_empty_map();
        set_port_tc(0, 1);
        set_port_tc(1, 3);
        set_port_tc(2, 1);
        set_port_tc(3, 3);

        request_arbitration();
        clear_expected_grant();
        expected_grant_g[3][3] = 1'b1;
        expect_grant("rr_tie_first_winner");

        request_arbitration();
        clear_expected_grant();
        expected_grant_g[1][3] = 1'b1;
        expect_grant("rr_tie_second_winner");

        reset_dut();

        // Case 6: all ports tied on the highest TC, verify RR walks the group.
        clear_empty_map();
        set_port_tc(0, 3);
        set_port_tc(1, 3);
        set_port_tc(2, 3);
        set_port_tc(3, 3);

        request_arbitration();
        clear_expected_grant();
        expected_grant_g[0][3] = 1'b1;
        expect_grant("rr_all_tied_0");

        request_arbitration();
        clear_expected_grant();
        expected_grant_g[1][3] = 1'b1;
        expect_grant("rr_all_tied_1");

        request_arbitration();
        clear_expected_grant();
        expected_grant_g[2][3] = 1'b1;
        expect_grant("rr_all_tied_2");

        request_arbitration();
        clear_expected_grant();
        expected_grant_g[3][3] = 1'b1;
        expect_grant("rr_all_tied_3");

        $display("tb_group_arb passed");
        $finish;
    end

endmodule
