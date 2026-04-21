`timescale 1ns/1ps
import systolic_array_pkg::*;

module tb_systolic_array_top;

    localparam int ACCUM_W = 32;
    localparam int WEIGHT_W = 8;
    localparam int ACTIVATION_W = 8;
    localparam int ARRAY_W = 4;
    localparam int MAT_W = 16;
    localparam int MAT_W_W = $clog2(MAT_W);
    localparam int NUM_COL_TILES = (MAT_W + ARRAY_W - 1) / ARRAY_W;
    localparam int EXPECTED_WORDS = MAT_W * NUM_COL_TILES;

    logic clk;
    logic rst_n;

    logic inst_load;
    instr_t instr_in;

    logic weight_rd_en_out;
    logic [MAT_W_W-1:0] weight_rd_addr_out;
    logic [MAT_W-1:0][WEIGHT_W-1:0] weight_in;

    logic act_rd_en_out;
    logic [MAT_W_W-1:0] act_rd_addr_out;
    logic [MAT_W-1:0][ACTIVATION_W-1:0] activation_in;

    logic valid_out;
    logic ready_in;
    logic [ARRAY_W-1:0][ACCUM_W-1:0] accum_out;

    logic [MAT_W-1:0][ACTIVATION_W-1:0] act_mem [0:MAT_W-1];
    logic [MAT_W-1:0][WEIGHT_W-1:0] weight_mem [0:MAT_W-1];

    logic [MAT_W-1:0][ACTIVATION_W-1:0] matrix_a [0:MAT_W-1];
    logic [MAT_W-1:0][WEIGHT_W-1:0] matrix_b [0:MAT_W-1];
    logic [MAT_W-1:0][ACCUM_W-1:0] golden_c [0:MAT_W-1];

    logic [ARRAY_W-1:0][ACCUM_W-1:0] expected_queue [$];
    int checked_count;
    int error_count;
    int timeout_cycles;
    bit enable_ready_stalls;

    systolic_array_top #(
        .ACCUM_W(ACCUM_W),
        .WEIGHT_W(WEIGHT_W),
        .ACTIVATION_W(ACTIVATION_W),
        .ARRAY_W(ARRAY_W),
        .MAT_W(MAT_W),
        .MAT_W_W(MAT_W_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .inst_load(inst_load),
        .instr_in(instr_in),
        .weight_rd_en_out(weight_rd_en_out),
        .weight_rd_addr_out(weight_rd_addr_out),
        .weight_in(weight_in),
        .act_rd_en_out(act_rd_en_out),
        .act_rd_addr_out(act_rd_addr_out),
        .activation_in(activation_in),
        .valid_out(valid_out),
        .ready_in(ready_in),
        .accum_out(accum_out)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("wave_systolic_array_top.vcd");
        $dumpvars(0, tb_systolic_array_top);
    end

    function automatic logic [ACTIVATION_W-1:0] make_activation(
        input int unsigned row,
        input int unsigned col
    );
        return ACTIVATION_W'(((row + 1) * 3 + (col + 2)) % 8);
    endfunction

    function automatic logic [WEIGHT_W-1:0] make_weight(
        input int unsigned row,
        input int unsigned col
    );
        return WEIGHT_W'(((row + 2) + (col * 5)) % 9);
    endfunction

    task automatic init_matrices;
        for (int row = 0; row < MAT_W; row++) begin
            for (int col = 0; col < MAT_W; col++) begin
                matrix_a[row][col] = make_activation(row, col);
                matrix_b[row][col] = make_weight(row, col);
            end
        end
    endtask

    task automatic load_memory_images;
        // Each SRAM word contains one full MAT_W-wide matrix row. The DUT selects
        // addresses through act_rd_addr_out/weight_rd_addr_out and sees the data
        // one cycle later through the read-response model below.
        for (int addr = 0; addr < MAT_W; addr++) begin
            for (int elem = 0; elem < MAT_W; elem++) begin
                act_mem[addr][elem] = matrix_a[addr][elem];
                weight_mem[addr][elem] = matrix_b[addr][elem];
            end
        end
    endtask

    task automatic build_golden_matrix;
        for (int row = 0; row < MAT_W; row++) begin
            for (int col = 0; col < MAT_W; col++) begin
                golden_c[row][col] = '0;
                for (int k = 0; k < MAT_W; k++) begin
                    golden_c[row][col] += ACCUM_W'(matrix_a[row][k]) *
                                          ACCUM_W'(matrix_b[k][col]);
                end
            end
        end
    endtask

    task automatic build_expected_output_queue;
        logic [ARRAY_W-1:0][ACCUM_W-1:0] expected_word;

        // Expected top-level drain order:
        // C[row 0, columns 0:ARRAY_W-1], C[row 1, columns 0:ARRAY_W-1], ...
        // then the next ARRAY_W-column group.
        expected_queue.delete();
        for (int col_tile = 0; col_tile < NUM_COL_TILES; col_tile++) begin
            for (int row = 0; row < MAT_W; row++) begin
                for (int lane = 0; lane < ARRAY_W; lane++) begin
                    int col;

                    col = (col_tile * ARRAY_W) + lane;
                    expected_word[lane] = (col < MAT_W) ? golden_c[row][col] : '0;
                end
                expected_queue.push_back(expected_word);
            end
        end
    endtask

    task automatic launch_instruction;
        @(posedge clk);
        #1;
        instr_in.num_tiles = MAX_TILES_W'(NUM_COL_TILES);
        inst_load = 1'b1;

        @(posedge clk);
        #1;
        inst_load = 1'b0;
        instr_in = '0;
    endtask

    // SRAM-like one-cycle read response model for the already-loaded A/B memories.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            activation_in <= '0;
            weight_in <= '0;
        end else begin
            if (act_rd_en_out) begin
                activation_in <= act_mem[act_rd_addr_out];
            end

            if (weight_rd_en_out) begin
                weight_in <= weight_mem[weight_rd_addr_out];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_in <= 1'b0;
        end else if (enable_ready_stalls) begin
            ready_in <= (($time / 10) % 7) != 3;
        end else begin
            ready_in <= 1'b1;
        end
    end

    initial begin
        if (!$value$plusargs("timeout_cycles=%0d", timeout_cycles)) begin
            timeout_cycles = 20000;
        end
        enable_ready_stalls = $test$plusargs("ready_stalls");

        rst_n = 1'b0;
        inst_load = 1'b0;
        instr_in = '0;
        activation_in = '0;
        weight_in = '0;
        checked_count = 0;
        error_count = 0;

        init_matrices();
        load_memory_images();
        build_golden_matrix();
        build_expected_output_queue();

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        launch_instruction();
    end

    initial begin
        forever begin
            @(posedge clk);
            if (rst_n && valid_out && ready_in) begin
                logic [ARRAY_W-1:0][ACCUM_W-1:0] expected;
                int row_idx;
                int col_base;

                if (expected_queue.size() == 0) begin
                    $error("Unexpected output word %0d after all expected outputs were checked",
                           checked_count);
                    error_count++;
                    $finish;
                end

                expected = expected_queue.pop_front();
                row_idx = checked_count % MAT_W;
                col_base = (checked_count / MAT_W) * ARRAY_W;

                for (int lane = 0; lane < ARRAY_W; lane++) begin
                    if (accum_out[lane] !== expected[lane]) begin
                        $error("Mismatch word=%0d row=%0d col=%0d: expected %0d, got %0d",
                               checked_count, row_idx, col_base + lane,
                               expected[lane], accum_out[lane]);
                        error_count++;
                    end
                end

                $display("CHECK word=%0d row=%0d cols=%0d:%0d accum={%0d, %0d, %0d, %0d}",
                         checked_count, row_idx, col_base, col_base + ARRAY_W - 1,
                         accum_out[0], accum_out[1], accum_out[2], accum_out[3]);
                checked_count++;

                if (checked_count == EXPECTED_WORDS) begin
                    if (error_count == 0) begin
                        $display("systolic_array_top PASSED: checked %0d output words",
                                 checked_count);
                    end else begin
                        $fatal(1, "systolic_array_top FAILED with %0d mismatches", error_count);
                    end
                    #20;
                    $finish;
                end
            end
        end
    end

    initial begin
        repeat (timeout_cycles) @(posedge clk);
        $fatal(1, "Timeout waiting for systolic_array_top outputs. checked=%0d expected=%0d",
               checked_count, EXPECTED_WORDS);
    end

endmodule
