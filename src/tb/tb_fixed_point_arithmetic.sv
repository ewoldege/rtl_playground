module tb_fixed_point_arithmetic;
    localparam WORD_LENGTH = 8;
    logic clk;
    logic signed [WORD_LENGTH-1:0] a, b;
    logic [WORD_LENGTH:0] c_add;
    logic [2*WORD_LENGTH-1:0] c_mult;
    logic input_valid, output_valid;
    logic signed[3:0] c_clipped_add;
    logic signed[WORD_LENGTH-3:0] c_round_add;
    
    fixed_point_arithmetic
    #(.WORD_LENGTH(WORD_LENGTH))
    dut
    (
        .clk (clk),
        .rst_n (1'b1),
        .valid_i(input_valid),
        .a(a),
        .b(b),
        .c_add(c_add),
        .c_mult(c_mult),
        .c_clipped_add(c_clipped_add),
        .c_round_add(c_round_add),
        .valid_o(output_valid)
    );

    initial begin 
        clk = 0;
        forever begin
            #10 clk = ~clk;
        end 
    end

    initial begin
        #100
        @(posedge clk);
        a = -8'd128; b = 8'd127; input_valid = 1;
        @(posedge clk);
        a = '0; b = '0; input_valid = 0;
        @(posedge clk); @(posedge clk); @(posedge clk); @(posedge clk);
        a = 8'd127; b = -8'd128; input_valid = 1;
        @(posedge clk);
        a = '0; b = '0; input_valid = 0;
        @(posedge clk); @(posedge clk); @(posedge clk); @(posedge clk);
        a = -8'd128; b = -8'd128; input_valid = 1;
        @(posedge clk);
        a = '0; b = '0; input_valid = 0;
        @(posedge clk); @(posedge clk); @(posedge clk); @(posedge clk);
        a = -8'd120; b = +8'd11; input_valid = 1;
        @(posedge clk);
        a = '0; b = '0; input_valid = 0;
        @(posedge clk); @(posedge clk); @(posedge clk); @(posedge clk);
        a = 8'd84; b = 8'd25; input_valid = 1;
        @(posedge clk);
        a = '0; b = '0; input_valid = 0;
    end 

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb);
        $display("Hello, start of test %0t", $time);
      #100000;
        #20
        $finish;
    end
endmodule
