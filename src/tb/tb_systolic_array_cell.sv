`timescale 1ns/1ps

module tb_systolic_array_cell;

    localparam int ACCUM_W = 32;
    localparam int WEIGHT_W = 8;
    localparam int ACTIVATION_W = 8;
    localparam int ARRAY_W = 4;
    localparam int NUM_ROWS = 4;
    localparam int NUM_RESULTS = NUM_ROWS * ARRAY_W;

    logic clk;
    logic rst_n;
    logic weight_load_in;
    logic [ARRAY_W-1:0][ARRAY_W-1:0][WEIGHT_W-1:0] weight_in;
    logic valid_in;
    logic [ARRAY_W-1:0][ACTIVATION_W-1:0] activation_in;
    logic [ARRAY_W-1:0] valid_out;
    logic [ARRAY_W-1:0][ACCUM_W-1:0] accum_out;

    logic [ARRAY_W-1:0][ARRAY_W-1:0][WEIGHT_W-1:0] weights;
    logic [NUM_ROWS-1:0][ARRAY_W-1:0][ACTIVATION_W-1:0] activations;
    logic [ARRAY_W-1:0][ACCUM_W-1:0] golden_queue [$];
    int checked_count;

    systolic_array_cell #(
        .ACCUM_W(ACCUM_W),
        .WEIGHT_W(WEIGHT_W),
        .ACTIVATION_W(ACTIVATION_W),
        .ARRAY_W(ARRAY_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .weight_load_in(weight_load_in),
        .weight_in(weight_in),
        .valid_in(valid_in),
        .activation_in(activation_in),
        .valid_out(valid_out),
        .accum_out(accum_out)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [ACCUM_W-1:0] golden_dot(
        input int unsigned row_idx,
        input int unsigned col_idx
    );
        logic [ACCUM_W-1:0] sum;
        begin
            sum = '0;
            for (int k = 0; k < ARRAY_W; k++) begin
                sum += ACCUM_W'(activations[row_idx][k]) *
                       ACCUM_W'(weights[k][col_idx]);
            end
            return sum;
        end
    endfunction

    task automatic push_expected_row(input int unsigned row_idx);
        logic [ARRAY_W-1:0][ACCUM_W-1:0] expected_row;

        for (int col = 0; col < ARRAY_W; col++) begin
            expected_row[col] = golden_dot(row_idx, col);
        end
        golden_queue.push_back(expected_row);
    endtask

    initial begin
        $dumpfile("wave_systolic_array_cell.vcd");
        $dumpvars(0, tb_systolic_array_cell);
    end

    initial begin
        rst_n = 1'b0;
        weight_load_in = 1'b0;
        weight_in = '0;
        valid_in = 1'b0;
        activation_in = '0;
        checked_count = 0;

        weights[0][0] = 8'd1;  weights[0][1] = 8'd2;  weights[0][2] = 8'd3;  weights[0][3] = 8'd4;
        weights[1][0] = 8'd5;  weights[1][1] = 8'd6;  weights[1][2] = 8'd7;  weights[1][3] = 8'd8;
        weights[2][0] = 8'd9;  weights[2][1] = 8'd10; weights[2][2] = 8'd11; weights[2][3] = 8'd12;
        weights[3][0] = 8'd13; weights[3][1] = 8'd14; weights[3][2] = 8'd15; weights[3][3] = 8'd16;

        activations[0][0] = 8'd1; activations[0][1] = 8'd0; activations[0][2] = 8'd2; activations[0][3] = 8'd1;
        activations[1][0] = 8'd0; activations[1][1] = 8'd1; activations[1][2] = 8'd1; activations[1][3] = 8'd0;
        activations[2][0] = 8'd3; activations[2][1] = 8'd2; activations[2][2] = 8'd1; activations[2][3] = 8'd0;
        activations[3][0] = 8'd1; activations[3][1] = 8'd1; activations[3][2] = 8'd1; activations[3][3] = 8'd1;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        @(posedge clk);
        #1;
        weight_in = weights;
        weight_load_in = 1'b1;

        @(posedge clk);
        #1;
        weight_load_in = 1'b0;
        weight_in = '0;

        for (int row = 0; row < NUM_ROWS; row++) begin
            @(posedge clk);
            #1;
            valid_in = 1'b1;
            activation_in = activations[row];
            push_expected_row(row);
        end

        @(posedge clk);
        #1;
        valid_in = 1'b0;
        activation_in = '0;
    end

    initial begin
        forever begin
            @(posedge clk);
            if (|valid_out) begin
                logic [ARRAY_W-1:0][ACCUM_W-1:0] expected;

                if (golden_queue.size() == 0) begin
                    $error("Unexpected accum_out vector with an empty golden queue");
                    $finish;
                end

                if (valid_out !== {ARRAY_W{1'b1}}) begin
                    $error("Expected all valid_out bits high, got valid_out=0x%0h",
                           valid_out);
                    $finish;
                end

                expected = golden_queue.pop_front();
                for (int col = 0; col < ARRAY_W; col++) begin
                    if (accum_out[col] !== expected[col]) begin
                        $error("Mismatch at row %0d col %0d: expected %0d, got %0d",
                               checked_count, col, expected[col], accum_out[col]);
                        $finish;
                    end
                end

                $display("PASS row %0d: accum={%0d, %0d, %0d, %0d}",
                         checked_count,
                         accum_out[0], accum_out[1], accum_out[2], accum_out[3]);
                checked_count++;
            end
        end
    end

    initial begin
        wait (checked_count == NUM_ROWS);
        $display("All %0d systolic_array_cell output rows PASSED", NUM_ROWS);
        #20;
        $finish;
    end

    initial begin
        #5000;
        $error("Timeout waiting for systolic_array_cell rows. checked=%0d expected=%0d",
               checked_count, NUM_ROWS);
        $finish;
    end

endmodule
