`timescale 1ns/1ps

module tb_fifo_fwft_sync;

    localparam int DATA_W = 8;
    localparam int DEPTH = 3;

    logic clk;
    logic rst_n;
    logic wr_en;
    logic [DATA_W-1:0] wr_data;
    logic full;
    logic rd_en;
    logic [DATA_W-1:0] rd_data;
    logic empty;

    fifo_fwft_sync #(
        .DATA_W(DATA_W),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .full(full),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .empty(empty)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic push(input logic [DATA_W-1:0] data);
        if (full) begin
            $fatal(1, "push while full, data=%0d", data);
        end

        wr_data = data;
        wr_en = 1'b1;
        @(posedge clk);
        #1;
        wr_en = 1'b0;
        wr_data = '0;
    endtask

    task automatic pop(input logic [DATA_W-1:0] expected);
        if (empty) begin
            $fatal(1, "pop while empty, expected=%0d", expected);
        end

        if (rd_data !== expected) begin
            $fatal(1, "rd_data mismatch before pop: expected=%0d got=%0d", expected, rd_data);
        end

        rd_en = 1'b1;
        @(posedge clk);
        #1;
        rd_en = 1'b0;
    endtask

    initial begin
        $dumpfile("wave_fifo_fwft_sync.vcd");
        $dumpvars(0, tb_fifo_fwft_sync);

        rst_n = 1'b0;
        wr_en = 1'b0;
        wr_data = '0;
        rd_en = 1'b0;

        repeat (3) @(posedge clk);
        #1;
        rst_n = 1'b1;

        push(8'd11);
        if (empty || rd_data !== 8'd11)
            $fatal(1, "FWFT first word mismatch: empty=%0b rd_data=%0d", empty, rd_data);

        push(8'd22);
        push(8'd33);
        if (!full)
            $fatal(1, "FIFO did not report full after %0d writes", DEPTH);

        pop(8'd11);
        pop(8'd22);
        pop(8'd33);
        if (!empty)
            $fatal(1, "FIFO did not report empty after draining");

        // These writes exercise pointer wrap for a non-power-of-two depth.
        push(8'd44);
        push(8'd55);
        pop(8'd44);
        push(8'd66);
        push(8'd77);
        if (!full)
            $fatal(1, "FIFO did not report full after wrapped writes");

        pop(8'd55);
        pop(8'd66);
        pop(8'd77);
        if (!empty)
            $fatal(1, "FIFO did not report empty after wrapped drain");

        $display("fifo_fwft_sync non-power-of-two depth test PASSED");
        #20;
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "Timeout in tb_fifo_fwft_sync");
    end

endmodule
