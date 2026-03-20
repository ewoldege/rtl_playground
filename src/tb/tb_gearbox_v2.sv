`timescale 1ns/1ps

module tb_gearbox_v2 #(
    parameter int IN_W              = 66,
    parameter int OUT_W             = 64,
    parameter int NUM_INPUT_WORDS   = 500,
    parameter int MAX_IN_BURST      = 8,
    parameter int MAX_IN_GAP        = 5,
    parameter int MAX_OUT_BURST     = 10,
    parameter int MAX_OUT_GAP       = 7,
    parameter int RESET_CYCLES      = 5,
    parameter int TIMEOUT_CYCLES    = 20000,
    parameter int SEED              = 32'h1234abcd,

    // 1: first accepted input bit is data_i[0]
    // 0: first accepted input bit is data_i[IN_W-1]
    parameter bit LSB_FIRST_STREAM  = 1'b0
);

    logic clk;
    logic rst_n;

    logic              ready_o;
    logic              valid_i;
    logic [IN_W-1:0]   data_i;

    logic              ready_i;
    logic              valid_o;
    logic [OUT_W-1:0]  data_o;

    gearbox_v2 #(
        .IN_W (IN_W),
        .OUT_W(OUT_W)
    ) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .ready_o(ready_o),
        .valid_i(valid_i),
        .data_i (data_i),
        .ready_i(ready_i),
        .valid_o(valid_o),
        .data_o (data_o)
    );

    // ------------------------------------------------------------
    // Reference model state
    // ------------------------------------------------------------
    bit stream_q[$];
    logic [OUT_W-1:0] exp_q[$];

    int unsigned in_hs_count;
    int unsigned out_hs_count;
    longint unsigned expected_total_outputs;

    logic             prev_stall;
    logic [OUT_W-1:0] prev_data_o;

    logic [OUT_W-1:0] exp_word;
    logic [OUT_W-1:0] exp_word_now;

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------
    // Reset / init
    // ------------------------------------------------------------
    initial begin
        rst_n    = 1'b0;
        valid_i  = 1'b0;
        data_i   = '0;
        ready_i  = 1'b0;

        void'($urandom(SEED));

        repeat (RESET_CYCLES) @(posedge clk);
        rst_n = 1'b1;
    end

    initial begin
        expected_total_outputs = (longint'(NUM_INPUT_WORDS) * IN_W) / OUT_W;
    end

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    function automatic logic [IN_W-1:0] gen_word(input int idx);
        logic [IN_W-1:0] tmp;
        begin
            for (int b = 0; b < IN_W; b++) begin
                tmp[b] = $urandom_range(0, 1);
            end

            // mix in index to make debugging easier
            for (int b = 0; b < IN_W; b++) begin
                tmp[b] ^= idx[b % 32];
            end

            return tmp;
        end
    endfunction

    task automatic push_input_word(input logic [IN_W-1:0] w);
        begin
            if (LSB_FIRST_STREAM) begin
                for (int i = 0; i < IN_W; i++) begin
                    stream_q.push_back(w[i]);
                end
            end
            else begin
                for (int i = IN_W-1; i >= 0; i--) begin
                    stream_q.push_back(w[i]);
                end
            end
        end
    endtask

    task automatic build_expected_words();
        logic [OUT_W-1:0] w;
        begin
            while (stream_q.size() >= OUT_W) begin
                w = '0;
                if (LSB_FIRST_STREAM) begin
                    for (int i = 0; i < OUT_W; i++) begin
                        w[i] = stream_q.pop_front();
                    end
                end
                else begin
                    for (int i = OUT_W-1; i >= 0; i--) begin
                        w[i] = stream_q.pop_front();
                    end
                end
                exp_q.push_back(w);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Scoreboard / protocol checks
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stream_q.delete();
            exp_q.delete();
            in_hs_count  <= 0;
            out_hs_count <= 0;
            prev_stall   <= 1'b0;
            prev_data_o  <= '0;
            exp_word     <= '0;
        end
        else begin
            // Hold check: if DUT was stalled last cycle, output must remain stable
            if (prev_stall) begin
                if (valid_o !== 1'b1) begin
                    $error("[%0t] ERROR: valid_o dropped while backpressured", $time);
                    $fatal;
                end
                if (data_o !== prev_data_o) begin
                    $error("[%0t] ERROR: data_o changed while backpressured. exp=%0h got=%0h",
                           $time, prev_data_o, data_o);
                    $fatal;
                end
            end

            // Input handshake
            if (valid_i && ready_o) begin
                push_input_word(data_i);
                build_expected_words();
                in_hs_count <= in_hs_count + 1;
            end

            // Output handshake
            if (valid_o && ready_i) begin
                if (exp_q.size() == 0) begin
                    $error("[%0t] ERROR: DUT produced output when expected queue is empty", $time);
                    $fatal;
                end

                exp_word_now = exp_q.pop_front();

                if (data_o !== exp_word_now) begin
                    $error("[%0t] ERROR: Output mismatch. exp=%0h got=%0h", $time, exp_word_now, data_o);
                    $fatal;
                end

                exp_word <= exp_word_now; // optional, just for debug visibility
                out_hs_count <= out_hs_count + 1;
            end

            prev_stall  <= (valid_o && !ready_i);
            if (valid_o && !ready_i) begin
                prev_data_o <= data_o;
            end
        end
    end

    // ------------------------------------------------------------
    // Upstream driver
    //
    // Use blocking assignments in initial blocks for Verilator.
    // Drive on negedge to avoid race with DUT posedge logic.
    // ------------------------------------------------------------
    initial begin : drive_input
        int issued_count;
        int accepted_count_local;
        int burst_left;
        int gap_left;

        issued_count         = 0;
        accepted_count_local = 0;
        burst_left           = 0;
        gap_left             = 0;

        wait (rst_n === 1'b1);

        forever begin
            @(negedge clk);

            if (!rst_n) begin
                valid_i = 1'b0;
                data_i  = '0;
                issued_count         = 0;
                accepted_count_local = 0;
                burst_left           = 0;
                gap_left             = 0;
            end
            else if (accepted_count_local >= NUM_INPUT_WORDS) begin
                valid_i = 1'b0;
            end
            else if (!valid_i) begin
                if (gap_left > 0) begin
                    valid_i = 1'b0;
                    gap_left--;
                end
                else begin
                    if (burst_left == 0) begin
                        burst_left = $urandom_range(1, MAX_IN_BURST);
                    end
                    data_i  = gen_word(issued_count);
                    valid_i = 1'b1;
                    issued_count++;
                end
            end
            else begin
                // valid_i already high; hold until handshake
                if (ready_o) begin
                    accepted_count_local++;
                    burst_left--;

                    if (accepted_count_local >= NUM_INPUT_WORDS) begin
                        valid_i = 1'b0;
                    end
                    else if (burst_left > 0) begin
                        data_i  = gen_word(issued_count);
                        valid_i = 1'b1;
                        issued_count++;
                    end
                    else begin
                        valid_i = 1'b0;
                        gap_left = $urandom_range(0, MAX_IN_GAP);
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Downstream ready driver
    // ------------------------------------------------------------
    initial begin : drive_output_ready
        int burst_left;
        int gap_left;

        burst_left = 0;
        gap_left   = 0;

        wait (rst_n === 1'b1);

        forever begin
            @(negedge clk);

            if (!rst_n) begin
                ready_i = 1'b0;
                burst_left = 0;
                gap_left   = 0;
            end
            else if (gap_left > 0) begin
                ready_i = 1'b0;
                gap_left--;
            end
            else begin
                if (burst_left == 0) begin
                    burst_left = $urandom_range(1, MAX_OUT_BURST);
                end

                ready_i = 1'b1;
                burst_left--;

                if (burst_left == 0) begin
                    gap_left = $urandom_range(0, MAX_OUT_GAP);
                end
            end
        end
    end

    // ------------------------------------------------------------
    // End of test / timeout
    // ------------------------------------------------------------
    initial begin : test_control
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_gearbox_v2);
        wait (rst_n === 1'b1);

        repeat (TIMEOUT_CYCLES) begin
            @(posedge clk);

            if ((in_hs_count == NUM_INPUT_WORDS) &&
                (out_hs_count == expected_total_outputs) &&
                (exp_q.size() == 0)) begin

                repeat (5) @(posedge clk);

                $display("--------------------------------------------------");
                $display("PASS tb_gearbox_v2");
                $display("  IN_W                 = %0d", IN_W);
                $display("  OUT_W                = %0d", OUT_W);
                $display("  NUM_INPUT_WORDS      = %0d", NUM_INPUT_WORDS);
                $display("  accepted inputs      = %0d", in_hs_count);
                $display("  accepted outputs     = %0d", out_hs_count);
                $display("  leftover bits        = %0d", stream_q.size());
                $display("--------------------------------------------------");
                $finish;
            end
        end

        $error("--------------------------------------------------");
        $error("TIMEOUT tb_gearbox_v2");
        $error("  IN_W                 = %0d", IN_W);
        $error("  OUT_W                = %0d", OUT_W);
        $error("  NUM_INPUT_WORDS      = %0d", NUM_INPUT_WORDS);
        $error("  accepted inputs      = %0d", in_hs_count);
        $error("  accepted outputs     = %0d", out_hs_count);
        $error("  expected outputs     = %0d", expected_total_outputs);
        $error("  queued exp words     = %0d", exp_q.size());
        $error("  leftover bits        = %0d", stream_q.size());
        $error("--------------------------------------------------");
        $fatal;
    end

endmodule