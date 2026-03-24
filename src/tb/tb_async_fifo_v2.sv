`timescale 1ns/1ps

module tb_async_fifo_v2;

    localparam int FIFO_DEPTH = 32;
    localparam int FIFO_WIDTH = 64;
    localparam int ADDR_W     = $clog2(FIFO_DEPTH);

    logic                  wclk;
    logic                  wrst_n;
    logic                  rclk;
    logic                  rrst_n;

    logic [FIFO_WIDTH-1:0] wdata;
    logic                  wren;
    logic                  full;

    logic                  rden;
    logic [FIFO_WIDTH-1:0] rdata;
    logic                  empty;

    async_fifo_v2 #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_WIDTH(FIFO_WIDTH)
    ) dut (
        .wclk   (wclk),
        .wrst_n (wrst_n),
        .rclk   (rclk),
        .rrst_n (rrst_n),
        .wdata  (wdata),
        .wren   (wren),
        .full   (full),
        .rden   (rden),
        .rdata  (rdata),
        .empty  (empty)
    );

    // ------------------------------------------------------------
    // Clocks
    // ------------------------------------------------------------
    initial wclk = 0;
    always #5 wclk = ~wclk;   // 100 MHz

    initial rclk = 0;
    always #7 rclk = ~rclk;   // ~71 MHz

    // ------------------------------------------------------------
    // Scoreboard
    // ------------------------------------------------------------
    logic [FIFO_WIDTH-1:0] exp_q[$];
    int errors = 0;

    // accepted write monitor
    always @(posedge wclk) begin
        if (wrst_n && wren && !full) begin
            exp_q.push_back(wdata);
            $display("[%0t] WRITE accepted data=0x%016h  qsize=%0d full=%0b",
                     $time, wdata, exp_q.size(), full);
        end
    end

    // accepted read checker
    // Assumes rdata is available same cycle as accepted read.
    // If your FIFO has registered read output, pipeline this by 1 cycle.
    always @(posedge rclk) begin : READ_CHECK
        logic [FIFO_WIDTH-1:0] exp;
        if (rrst_n && rden && !empty) begin
            if (exp_q.size() == 0) begin
                $error("[%0t] Read accepted but scoreboard empty", $time);
                errors++;
            end
            else begin
                exp = exp_q.pop_front();
                #1;
                if (rdata !== exp) begin
                    $error("[%0t] READ mismatch got=0x%016h exp=0x%016h",
                           $time, rdata, exp);
                    errors++;
                end
                else begin
                    $display("[%0t] READ  accepted data=0x%016h  qsize=%0d empty=%0b",
                             $time, rdata, exp_q.size(), empty);
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    task automatic reset_dut();
        begin
            wdata  = '0;
            wren   = 1'b0;
            rden   = 1'b0;
            wrst_n = 1'b0;
            rrst_n = 1'b0;

            repeat (4) @(posedge wclk);
            repeat (4) @(posedge rclk);

            wrst_n = 1'b1;
            rrst_n = 1'b1;

            // give synchronizers time to settle
            repeat (4) @(posedge wclk);
            repeat (4) @(posedge rclk);
        end
    endtask

    task automatic write_one(input logic [FIFO_WIDTH-1:0] data);
        begin
            @(negedge wclk);
            wdata = data;
            wren  = 1'b1;
            @(negedge wclk);
            wren  = 1'b0;
            wdata = '0;
        end
    endtask

    task automatic read_one();
        begin
            @(negedge rclk);
            rden = 1'b1;
            @(negedge rclk);
            rden = 1'b0;
        end
    endtask

    task automatic wait_wclk(input int n);
        repeat (n) @(posedge wclk);
    endtask

    task automatic wait_rclk(input int n);
        repeat (n) @(posedge rclk);
    endtask

    task automatic expect_flag(
        input string name,
        input logic actual,
        input logic expected
    );
        begin
            if (actual !== expected) begin
                $error("[%0t] %s expected=%0b actual=%0b", $time, name, expected, actual);
                errors++;
            end
            else begin
                $display("[%0t] %s correct: %0b", $time, name, actual);
            end
        end
    endtask

    // Fill until FULL is observed or timeout
    task automatic fill_until_full();
        int i;
        begin
            $display("\n--- Fill until FULL ---");
            i = 0;
            while (!full && i < FIFO_DEPTH + 8) begin
                write_one(64'hA000_0000_0000_0000 + i);
                i++;
                wait_wclk(1);
            end

            // allow a few extra cycles for synced pointer visibility
            if (!full) begin
                wait_wclk(4);
            end

            if (!full) begin
                $error("[%0t] FULL never asserted after %0d writes", $time, i);
                errors++;
            end
            else begin
                $display("[%0t] FULL asserted after %0d write attempts", $time, i);
            end
        end
    endtask

    // Drain until EMPTY is observed or timeout
    task automatic drain_until_empty();
        int i;
        begin
            $display("\n--- Drain until EMPTY ---");
            i = 0;
            while (!empty && i < FIFO_DEPTH + 8) begin
                read_one();
                i++;
                wait_rclk(1);
            end

            // allow a few extra cycles for synced pointer visibility
            if (!empty) begin
                wait_rclk(4);
            end

            if (!empty) begin
                $error("[%0t] EMPTY never asserted after %0d reads", $time, i);
                errors++;
            end
            else begin
                $display("[%0t] EMPTY asserted after %0d read attempts", $time, i);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    initial begin
        reset_dut();

        $display("\n================ RESET CHECK ================\n");
        expect_flag("empty_after_reset", empty, 1'b1);
        expect_flag("full_after_reset",  full,  1'b0);

        $display("\n================ EMPTY STRESS ================\n");
        // Try reading while empty: should remain empty, no scoreboard pop
        repeat (3) begin
            read_one();
            wait_rclk(2);
            expect_flag("empty_during_underflow_attempt", empty, 1'b1);
        end

        $display("\n================ BASIC WRITE/READ ================\n");
        write_one(64'h1111);
        wait_wclk(3);
        expect_flag("empty_after_one_write_not_expected", empty, 1'b0);

        read_one();
        wait_rclk(3);
        expect_flag("empty_after_single_drain", empty, 1'b1);

        $display("\n================ FULL STRESS ================\n");
        fill_until_full();

        // Try writing while full: should not be accepted
        begin
            int qsize_before;
            qsize_before = exp_q.size();

            $display("\n--- Attempt writes while FULL ---");
            repeat (3) begin
                write_one(64'hDEAD_BEEF_DEAD_BEEF);
                wait_wclk(1);
            end

            if (exp_q.size() != qsize_before) begin
                $error("[%0t] Scoreboard size changed during full condition. before=%0d after=%0d",
                       $time, qsize_before, exp_q.size());
                errors++;
            end

            expect_flag("full_after_overflow_attempts", full, 1'b1);
        end

        $display("\n================ DRAIN TO EMPTY ================\n");
        drain_until_empty();

        // Try reading while empty again
        begin
            int qsize_before;
            qsize_before = exp_q.size();

            $display("\n--- Attempt reads while EMPTY ---");
            repeat (3) begin
                read_one();
                wait_rclk(1);
            end

            if (exp_q.size() != qsize_before) begin
                $error("[%0t] Scoreboard size changed during empty condition. before=%0d after=%0d",
                       $time, qsize_before, exp_q.size());
                errors++;
            end

            expect_flag("empty_after_underflow_attempts", empty, 1'b1);
        end

        $display("\n================ WRAPAROUND STRESS ================\n");
        // Repeated partial fills and drains to exercise pointer wrap
        repeat (3) begin : WRAP_TEST
            int k;

            $display("\n--- Partial fill ---");
            for (k = 0; k < FIFO_DEPTH/2 + 3; k++) begin
                write_one(64'h5000_0000_0000_0000 + k);
            end
            wait_wclk(3);

            $display("\n--- Partial drain ---");
            for (k = 0; k < FIFO_DEPTH/2 - 1; k++) begin
                read_one();
            end
            wait_rclk(3);
        end

        $display("\n================ FINAL DRAIN ================\n");
        // Drain anything left
        while (exp_q.size() > 0) begin
            read_one();
        end
        wait_rclk(4);
        expect_flag("empty_at_end", empty, 1'b1);

        $display("\n================ DONE ================\n");
        if (errors == 0) begin
            $display("TEST PASSED");
        end
        else begin
            $display("TEST FAILED, errors=%0d", errors);
        end

        $finish;
    end

endmodule