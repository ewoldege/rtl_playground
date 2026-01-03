`timescale 1ns/1ps

module tb_simd_vector_mac;

    // ------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------
    parameter int NUM_LANES     = 4;
    parameter int ELEM_W        = 16;
    parameter int MAX_NUM_ELEM  = 64;
    parameter int VEC_MAC_DATA_W = 2*ELEM_W + $clog2(MAX_NUM_ELEM);

    parameter int NUM_VECTORS = 500;

    // ------------------------------------------------------------------
    // Clock / Reset
    // ------------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100 MHz
    end

    // ------------------------------------------------------------------
    // DUT Signals
    // ------------------------------------------------------------------
    logic valid_i;
    logic start_i;
    logic last_i;

    logic signed [NUM_LANES-1:0][ELEM_W-1:0] A;
    logic signed [NUM_LANES-1:0][ELEM_W-1:0] B;

    logic vector_mac_valid_o;
    logic signed [VEC_MAC_DATA_W-1:0] vector_mac_data_o;

    // ------------------------------------------------------------------
    // Instantiate DUT
    // ------------------------------------------------------------------
    simd_vector_mac #(
        .NUM_LANES(NUM_LANES),
        .ELEM_W(ELEM_W),
        .MAX_NUM_ELEM(MAX_NUM_ELEM),
        .VEC_MAC_DATA_W(VEC_MAC_DATA_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_i(valid_i),
        .start_i(start_i),
        .last_i(last_i),
        .A(A),
        .B(B),
        .vector_mac_valid_o(vector_mac_valid_o),
        .vector_mac_data_o(vector_mac_data_o)
    );

    // ------------------------------------------------------------------
    // Golden scoreboard
    // ------------------------------------------------------------------
    logic signed [VEC_MAC_DATA_W-1:0] golden_queue [$];

    int vectors_sent;
    int vectors_checked;

    // ------------------------------------------------------------------
    // Reset
    // ------------------------------------------------------------------
    initial begin
        rst_n   = 0;
        valid_i = 0;
        start_i = 0;
        last_i  = 0;
        A = '0;
        B = '0;

        #25;
        rst_n = 1;
    end

    // ------------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------------
    initial begin
        vectors_sent = 0;

        wait(rst_n);

        repeat (NUM_VECTORS) begin
            int vec_len;
            int elems_sent;
            logic signed [VEC_MAC_DATA_W-1:0] acc;

            // Random vector length (number of scalar elements)
            vec_len = $urandom_range(1, MAX_NUM_ELEM);
            elems_sent = 0;
            acc = '0;

            while (elems_sent < vec_len) begin
                int lane_count;

                lane_count = (vec_len - elems_sent >= NUM_LANES) ?
                              NUM_LANES : (vec_len - elems_sent);

                @(posedge clk);
                #1; // skew to avoid XSIM sampling issue

                valid_i = 1;
                start_i = (elems_sent == 0);
                last_i  = (elems_sent + lane_count == vec_len);

                // Drive lanes
                for (int l = 0; l < NUM_LANES; l++) begin
                    if (l < lane_count) begin
                        // Force each A and B element to signed ELEM_W
                        A[l] = $urandom_range(-(2**(ELEM_W-1)), 2**(ELEM_W-1)-1);
                        B[l] = $urandom_range(-(2**(ELEM_W-1)), 2**(ELEM_W-1)-1);

                        // Make multiplication explicitly signed and extend to accumulator width
                        acc += $signed(A[l]) * $signed(B[l]);
                    end else begin
                        A[l] = '0;
                        B[l] = '0;
                    end
                end

                elems_sent += lane_count;
            end

            // Deassert valid cleanly
            @(posedge clk);
            #1;
            valid_i = 0;
            start_i = 0;
            last_i  = 0;
            A = '0;
            B = '0;

            golden_queue.push_back(acc);
            vectors_sent++;
        end
    end

    // ------------------------------------------------------------------
    // Checker
    // ------------------------------------------------------------------
    initial begin
        vectors_checked = 0;

        forever begin
            @(posedge clk);
            if (vector_mac_valid_o) begin
                if (golden_queue.size() == 0) begin
                    $error("Unexpected output from DUT!");
                end else begin
                    logic signed [VEC_MAC_DATA_W-1:0] expected;
                    expected = golden_queue.pop_front();

                    if (vector_mac_data_o !== expected) begin
                        $error("Mismatch! Expected %0d, got %0d",
                               expected, vector_mac_data_o);
                    end else begin
                        $display("PASS vector %0d: result = %0d",
                                 vectors_checked, vector_mac_data_o);
                    end

                    vectors_checked++;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // End simulation
    // ------------------------------------------------------------------
    initial begin
        wait(vectors_checked == NUM_VECTORS);
        $display("======================================");
        $display("All %0d vectors PASSED", NUM_VECTORS);
        $display("======================================");
        #20;
        $finish;
    end

endmodule
