`timescale 1ns/1ps
import floating_point_pkg::*;

module tb_floating_point_mult;

    localparam int NUM_DIRECTED_TESTS = 16;
    localparam int NUM_RANDOM_TESTS = 128;
    localparam int TIMEOUT_CYCLES = 2000;

    logic clk;
    logic rst_n;
    fl_6 a_in;
    fl_6 b_in;
    logic valid_in;
    fl_6 c_out;
    logic overflow;
    logic valid_out;

    fl_6 expected_queue [$];
    logic expected_overflow_queue [$];
    fl_6 expected;
    logic expected_overflow;
    int checked_count;
    int error_count;
    int expected_count;
    int unsigned rng_state;

    floating_point_mult dut (
        .clk(clk),
        .rst_n(rst_n),
        .a_in(a_in),
        .b_in(b_in),
        .valid_in(valid_in),
        .c_out(c_out),
        .overflow(overflow),
        .valid_out(valid_out)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("wave_floating_point_mult.vcd");
        $dumpvars(0, tb_floating_point_mult);
    end

    function automatic fl_6 make_fl(
        input logic sign,
        input logic [7:0] exp,
        input logic [6:0] frac
    );
        fl_6 value;

        value.sign = sign;
        value.exp = exp;
        value.frac = frac;
        return value;
    endfunction

    function automatic logic is_zero(input fl_6 value);
        return (value.exp == '0) && (value.frac == '0);
    endfunction

    function automatic logic [7:0] round_to_nearest_even_ref(
        input logic [14:0] raw
    );
        logic sticky;
        logic guard_bit;
        logic lsb;
        logic round_up;
        logic [7:0] kept;
        logic [8:0] rounded;

        sticky = |raw[5:0];
        guard_bit = raw[6];
        lsb = raw[7];
        kept = raw[14:7];
        round_up = guard_bit && (sticky || lsb);
        rounded = {1'b0, kept} + {8'b0, round_up};

        return rounded[8] ? 8'hff : rounded[7:0];
    endfunction

    function automatic fl_6 multiply_ref(input fl_6 a, input fl_6 b);
        logic [8:0] exp_raw;
        logic [15:0] mantissa_raw;
        logic [8:0] exp_aligned;
        logic [15:0] mantissa_aligned;
        logic [7:0] rounded_mantissa;
        fl_6 result;

        if (is_zero(a) || is_zero(b)) begin
            return make_fl(1'b0, 8'h00, 7'h00);
        end

        exp_raw = {1'b0, a.exp} + {1'b0, b.exp};
        mantissa_raw = {1'b1, a.frac} * {1'b1, b.frac};

        if (mantissa_raw[15]) begin
            mantissa_aligned = mantissa_raw >> 1;
            exp_aligned = exp_raw + 9'd1;
        end else begin
            mantissa_aligned = mantissa_raw;
            exp_aligned = exp_raw;
        end

        rounded_mantissa = round_to_nearest_even_ref(mantissa_aligned[14:0]);

        result.sign = a.sign ^ b.sign;
        result.exp = exp_aligned[7:0];
        result.frac = rounded_mantissa[6:0];
        return result;
    endfunction

    function automatic logic overflow_ref(input fl_6 a, input fl_6 b);
        logic [8:0] exp_raw;
        logic [15:0] mantissa_raw;
        logic [8:0] exp_aligned;

        if (is_zero(a) || is_zero(b)) begin
            return 1'b0;
        end

        exp_raw = {1'b0, a.exp} + {1'b0, b.exp};
        mantissa_raw = {1'b1, a.frac} * {1'b1, b.frac};
        exp_aligned = mantissa_raw[15] ? (exp_raw + 9'd1) : exp_raw;

        return exp_aligned[8];
    endfunction

    function automatic logic fl_equal(input fl_6 actual, input fl_6 exp);
        return (actual.sign === exp.sign) &&
               (actual.exp === exp.exp) &&
               (actual.frac === exp.frac);
    endfunction

    function automatic fl_6 random_normal_fl;
        fl_6 value;

        rng_state = (rng_state * 32'd1664525) + 32'd1013904223;
        value.sign = rng_state[31];
        value.exp = rng_state[23:16];
        value.frac = rng_state[14:8];

        if (value.exp == 8'h00) begin
            value.exp = 8'h01;
        end

        return value;
    endfunction

    task automatic drive_one(
        input fl_6 a,
        input fl_6 b,
        input bit insert_bubble_after
    );
        fl_6 exp;
        logic exp_overflow;

        exp = multiply_ref(a, b);
        exp_overflow = overflow_ref(a, b);

        @(posedge clk);
        #1;
        a_in = a;
        b_in = b;
        valid_in = 1'b1;
        expected_queue.push_back(exp);
        expected_overflow_queue.push_back(exp_overflow);
        expected_count++;

        if (insert_bubble_after) begin
            @(posedge clk);
            #1;
            valid_in = 1'b0;
            a_in = '0;
            b_in = '0;
        end
    endtask

    task automatic drive_directed_tests;
        drive_one(make_fl(1'b0, 8'h00, 7'h00), make_fl(1'b0, 8'h12, 7'h01), 1'b0);
        drive_one(make_fl(1'b1, 8'h22, 7'h10), make_fl(1'b0, 8'h00, 7'h00), 1'b1);
        drive_one(make_fl(1'b0, 8'h01, 7'h00), make_fl(1'b0, 8'h01, 7'h00), 1'b0);
        drive_one(make_fl(1'b1, 8'h01, 7'h00), make_fl(1'b0, 8'h01, 7'h00), 1'b0);
        drive_one(make_fl(1'b1, 8'h04, 7'h20), make_fl(1'b1, 8'h03, 7'h10), 1'b1);
        drive_one(make_fl(1'b0, 8'h07, 7'h7f), make_fl(1'b0, 8'h02, 7'h7f), 1'b0);
        drive_one(make_fl(1'b0, 8'h10, 7'h40), make_fl(1'b1, 8'h08, 7'h20), 1'b0);
        drive_one(make_fl(1'b1, 8'h55, 7'h55), make_fl(1'b1, 8'h11, 7'h33), 1'b1);
        drive_one(make_fl(1'b0, 8'h80, 7'h01), make_fl(1'b0, 8'h10, 7'h02), 1'b0);
        drive_one(make_fl(1'b0, 8'hf0, 7'h7e), make_fl(1'b1, 8'h20, 7'h7d), 1'b0);
        drive_one(make_fl(1'b1, 8'hfe, 7'h7f), make_fl(1'b0, 8'h02, 7'h7f), 1'b1);
        drive_one(make_fl(1'b0, 8'h33, 7'h08), make_fl(1'b0, 8'h44, 7'h04), 1'b0);
        drive_one(make_fl(1'b1, 8'h12, 7'h7c), make_fl(1'b0, 8'h05, 7'h03), 1'b0);
        drive_one(make_fl(1'b0, 8'h09, 7'h11), make_fl(1'b1, 8'h09, 7'h22), 1'b1);
        drive_one(make_fl(1'b0, 8'h7f, 7'h40), make_fl(1'b0, 8'h01, 7'h40), 1'b0);
        drive_one(make_fl(1'b1, 8'h01, 7'h01), make_fl(1'b1, 8'h01, 7'h01), 1'b1);
    endtask

    task automatic drive_random_tests;
        fl_6 a;
        fl_6 b;

        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            a = random_normal_fl();
            b = random_normal_fl();

            if ((i % 17) == 0) begin
                a = make_fl(a.sign, 8'h00, 7'h00);
            end else if ((i % 23) == 0) begin
                b = make_fl(b.sign, 8'h00, 7'h00);
            end

            drive_one(a, b, (i % 5) == 2);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        a_in = '0;
        b_in = '0;
        valid_in = 1'b0;
        checked_count = 0;
        error_count = 0;
        expected_count = 0;
        rng_state = 32'hc001_cafe;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        drive_directed_tests();
        drive_random_tests();

        @(posedge clk);
        #1;
        valid_in = 1'b0;
        a_in = '0;
        b_in = '0;
    end

    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            if (expected_queue.size() == 0) begin
                $error("Unexpected valid_out with no queued expected value: got sign=%0b exp=0x%02h frac=0x%02h overflow=%0b",
                       c_out.sign, c_out.exp, c_out.frac, overflow);
                error_count++;
            end else begin
                expected = expected_queue.pop_front();
                expected_overflow = expected_overflow_queue.pop_front();
                if (!fl_equal(c_out, expected) || (overflow !== expected_overflow)) begin
                    $error("Mismatch %0d: expected sign=%0b exp=0x%02h frac=0x%02h overflow=%0b, got sign=%0b exp=0x%02h frac=0x%02h overflow=%0b",
                           checked_count,
                           expected.sign, expected.exp, expected.frac, expected_overflow,
                           c_out.sign, c_out.exp, c_out.frac, overflow);
                    error_count++;
                end else begin
                    $display("PASS %0d: sign=%0b exp=0x%02h frac=0x%02h overflow=%0b",
                             checked_count, c_out.sign, c_out.exp, c_out.frac, overflow);
                end

                checked_count++;
            end
        end
    end

    initial begin
        wait (checked_count == (NUM_DIRECTED_TESTS + NUM_RANDOM_TESTS));
        repeat (4) @(posedge clk);

        if (error_count == 0) begin
            $display("All %0d floating_point_mult tests PASSED", checked_count);
        end else begin
            $error("%0d floating_point_mult tests FAILED out of %0d checked",
                   error_count, checked_count);
        end

        $finish;
    end

    initial begin
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $error("Timeout waiting for floating_point_mult outputs. checked=%0d expected=%0d queued=%0d overflow_queued=%0d errors=%0d",
               checked_count, expected_count, expected_queue.size(), expected_overflow_queue.size(), error_count);
        $finish;
    end

endmodule
