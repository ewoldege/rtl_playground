module tb_fixed_point_arithmetic;
    localparam WORD_LENGTH = 16;
    logic clk;
    logic [WORD_LENGTH-1:0] a, b;
    logic [WORD_LENGTH:0] c_add;
    logic [2*WORD_LENGTH-1:0] c_mult;
    logic input_valid, output_valid;
    
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
        a = 16'd100; b = 16'd50; input_valid = 1;
        @(posedge clk);
        a = '0; b = '0; input_valid = 0;
        @(posedge clk); @(posedge clk); @(posedge clk); @(posedge clk);
        a = 16'd10000; b = 16'd12546; input_valid = 1;
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
