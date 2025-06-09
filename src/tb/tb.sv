module tb;
    logic clk;
    logic upstream_valid;
    logic upstream_ready;
    logic [31:0] data, datb, datc;
    logic downstream_valid;
    logic downstream_ready;

    typedef struct packed {
        logic [31:0]  result;
        logic         induced_err;
    } scoreboard_struct_t;

    scoreboard_struct_t expected_result_queue[$];
    scoreboard_struct_t expected_result_struct;
    
    adder dut(
        .clk (clk),
        .rst (1'b0),
        .i_req(upstream_valid),
        .i_data(data),
        .i_datb(datb),
        .i_ack(upstream_ready),
        .o_req(downstream_valid),
        .o_datc(datc),
        .o_ack(downstream_ready)
    );

    initial begin 
        clk = 0;
        forever begin
            #10 clk = ~clk;
        end 
    end

    logic [31:0] tb_data, tb_datb;
    logic [31:0] expected_result;
    logic [31:0]  random_err_bus;
    logic induced_err;

    initial begin
        downstream_ready = 1;
        forever begin
            if (upstream_ready) begin
                random_err_bus = $urandom_range(0,15);
                if (random_err_bus[3:0] == 4'h1)
                    induced_err = 1;
                else
                    induced_err = 0;
                tb_data = $urandom();
                tb_data[31] = 1'b0;
                data = tb_data;
                tb_datb = $urandom();
                tb_datb[31] = 1'b0;
                datb = tb_datb;
                expected_result = data + datb;
                if (induced_err)
                    expected_result[31] = ~expected_result[31];
                else
                    expected_result[31] = expected_result[31];
                upstream_valid = 1;
            end else begin
                upstream_valid = 0;
                tb_data = '0;
                tb_datb = '0;
                data = '0;
                datb = '0;
                expected_result = '0;
            end
        @(posedge clk);
        end 
    end

    assign expected_result_struct.result = expected_result;
    assign expected_result_struct.induced_err = induced_err;

    always_ff @(posedge clk) begin
        if (upstream_ready & upstream_valid)
            expected_result_queue.push_back(expected_result_struct);
    end

    // Scoreboard
    scoreboard_struct_t scoreboard_expected_result;
    logic check_the_value;
    logic [31:0] checked_values, passing_values, pass_induced_err_values;
    always_ff @( posedge clk ) begin : scoreboard
        if (downstream_ready & downstream_valid) begin
            check_the_value = 1;
            checked_values = checked_values + 1;
            if (expected_result_queue.size() == 0)
                $error("No expected result for output of DUT");
            scoreboard_expected_result = expected_result_queue.pop_front();
        end else begin
            check_the_value = 0;
            checked_values = checked_values;
        end
        if (check_the_value) begin
            if (scoreboard_expected_result.result == datc) begin
                $display("Successful addition");
                passing_values = passing_values + 1;
            end else begin
                if (scoreboard_expected_result.induced_err) begin
                    $display("Successful addition - induced error");
                    pass_induced_err_values = pass_induced_err_values + 1;
                    passing_values = passing_values + 1;
                end else begin
                    $display("Failed addition, expected result %h, actual result %h, time = %t", scoreboard_expected_result.result, datc, $time);
                    passing_values = passing_values;
                end
            end
        end
    end

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb);
        $display("Hello, start of test %0t", $time);
        #100000;
        $display("Checked values = %d . Passing values = %d, Passing with Induced Error", checked_values, passing_values, pass_induced_err_values);
        #20
        $finish;
    end
endmodule
