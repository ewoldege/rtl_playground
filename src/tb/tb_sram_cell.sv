`timescale 1ns/1ps

module tb_sram_cell;

    localparam int DATA_W = 32;
    localparam int DEPTH  = 16;
    localparam int ADDR_W = $clog2(DEPTH);
    localparam int BYTE_W = 8;
    localparam int BYTE_EN_W = DATA_W / BYTE_W;

    logic clk;
    logic rst_n;
    logic en;
    logic wr_en;
    logic [ADDR_W-1:0] wr_addr;
    logic [DATA_W-1:0] wr_data;
    logic [BYTE_EN_W-1:0] byte_en;
    logic rd_en;
    logic [ADDR_W-1:0] rd_addr;

    logic [DATA_W-1:0] rd_data_read_first;
    logic              rd_valid_read_first;
    logic [DATA_W-1:0] rd_data_write_first;
    logic              rd_valid_write_first;
    logic [DATA_W-1:0] rd_data_no_change;
    logic              rd_valid_no_change;

    int errors;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    sram_cell #(
        .DATA_W(DATA_W),
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W),
        .BYTE_W(BYTE_W),
        .BYTE_EN_W(BYTE_EN_W),
        .RDW_MODE(0)
    ) dut_read_first (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .byte_en(byte_en),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data_read_first),
        .rd_valid(rd_valid_read_first)
    );

    sram_cell #(
        .DATA_W(DATA_W),
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W),
        .BYTE_W(BYTE_W),
        .BYTE_EN_W(BYTE_EN_W),
        .RDW_MODE(1)
    ) dut_write_first (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .byte_en(byte_en),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data_write_first),
        .rd_valid(rd_valid_write_first)
    );

    sram_cell #(
        .DATA_W(DATA_W),
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W),
        .BYTE_W(BYTE_W),
        .BYTE_EN_W(BYTE_EN_W),
        .RDW_MODE(2)
    ) dut_no_change (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .byte_en(byte_en),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data_no_change),
        .rd_valid(rd_valid_no_change)
    );

    task automatic drive_cycle(
        input logic en_i,
        input logic wr_en_i,
        input logic [ADDR_W-1:0] wr_addr_i,
        input logic [DATA_W-1:0] wr_data_i,
        input logic [BYTE_EN_W-1:0] byte_en_i,
        input logic rd_en_i,
        input logic [ADDR_W-1:0] rd_addr_i
    );
        begin
            en      <= en_i;
            wr_en   <= wr_en_i;
            wr_addr <= wr_addr_i;
            wr_data <= wr_data_i;
            byte_en <= byte_en_i;
            rd_en   <= rd_en_i;
            rd_addr <= rd_addr_i;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic expect_valid(
        input logic exp_valid
    );
        begin
            if (rd_valid_read_first !== exp_valid) begin
                $display("[%0t] ERROR: read-first valid exp=%0b got=%0b",
                         $time, exp_valid, rd_valid_read_first);
                errors++;
            end
            if (rd_valid_write_first !== exp_valid) begin
                $display("[%0t] ERROR: write-first valid exp=%0b got=%0b",
                         $time, exp_valid, rd_valid_write_first);
                errors++;
            end
            if (rd_valid_no_change !== exp_valid) begin
                $display("[%0t] ERROR: no-change valid exp=%0b got=%0b",
                         $time, exp_valid, rd_valid_no_change);
                errors++;
            end
        end
    endtask

    task automatic expect_data(
        input logic [DATA_W-1:0] exp_read_first,
        input logic [DATA_W-1:0] exp_write_first,
        input logic [DATA_W-1:0] exp_no_change
    );
        begin
            if (rd_data_read_first !== exp_read_first) begin
                $display("[%0t] ERROR: read-first data exp=0x%08h got=0x%08h",
                         $time, exp_read_first, rd_data_read_first);
                errors++;
            end
            if (rd_data_write_first !== exp_write_first) begin
                $display("[%0t] ERROR: write-first data exp=0x%08h got=0x%08h",
                         $time, exp_write_first, rd_data_write_first);
                errors++;
            end
            if (rd_data_no_change !== exp_no_change) begin
                $display("[%0t] ERROR: no-change data exp=0x%08h got=0x%08h",
                         $time, exp_no_change, rd_data_no_change);
                errors++;
            end
        end
    endtask

    initial begin
        $dumpfile("wave_sram_cell.vcd");
        $dumpvars(0, tb_sram_cell);

        errors  = 0;
        rst_n   = 1'b0;
        en      = 1'b0;
        wr_en   = 1'b0;
        wr_addr = '0;
        wr_data = '0;
        byte_en = '0;
        rd_en   = 1'b0;
        rd_addr = '0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        #1;
        expect_valid(1'b0);
        expect_data('0, '0, '0);

        drive_cycle(1'b1, 1'b1, 4'd3, 32'h1122_3344, 4'b1111, 1'b0, '0);
        expect_valid(1'b0);

        drive_cycle(1'b1, 1'b0, '0, '0, '0, 1'b1, 4'd3);
        expect_valid(1'b1);
        expect_data(32'h1122_3344, 32'h1122_3344, 32'h1122_3344);

        drive_cycle(1'b1, 1'b1, 4'd3, 32'haabb_ccdd, 4'b0101, 1'b0, '0);
        drive_cycle(1'b1, 1'b0, '0, '0, '0, 1'b1, 4'd3);
        expect_valid(1'b1);
        expect_data(32'h11bb_33dd, 32'h11bb_33dd, 32'h11bb_33dd);

        drive_cycle(1'b1, 1'b1, 4'd4, 32'hdead_beef, 4'b1111, 1'b1, 4'd3);
        expect_valid(1'b1);
        expect_data(32'h11bb_33dd, 32'h11bb_33dd, 32'h11bb_33dd);

        drive_cycle(1'b1, 1'b0, '0, '0, '0, 1'b1, 4'd4);
        expect_valid(1'b1);
        expect_data(32'hdead_beef, 32'hdead_beef, 32'hdead_beef);

        drive_cycle(1'b1, 1'b1, 4'd3, 32'h5566_7788, 4'b1111, 1'b1, 4'd3);
        expect_valid(1'b1);
        expect_data(32'h11bb_33dd, 32'h5566_7788, 32'hdead_beef);

        drive_cycle(1'b1, 1'b0, '0, '0, '0, 1'b1, 4'd3);
        expect_valid(1'b1);
        expect_data(32'h5566_7788, 32'h5566_7788, 32'h5566_7788);

        drive_cycle(1'b0, 1'b0, '0, '0, '0, 1'b1, 4'd3);
        expect_valid(1'b0);

        if (errors == 0) begin
            $display("SRAM cell test PASSED");
        end else begin
            $display("SRAM cell test FAILED with %0d errors", errors);
            $fatal(1);
        end

        $finish;
    end

endmodule
