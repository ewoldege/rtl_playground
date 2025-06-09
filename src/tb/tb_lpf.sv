module tb_lpf;
    localparam TAP_NUM = 16;
    localparam SAMPLE_LEN = 8;
    localparam COEFFICIENT_LEN = 16;
    logic clk;
    logic signed [SAMPLE_LEN-1:0] sample_i;
    logic signed [TAP_NUM-1:0][COEFFICIENT_LEN-1:0] coeff_i;
    logic input_valid, output_valid;
    
    lpf
    #(.TAP_NUM(TAP_NUM), .SAMPLE_LEN(SAMPLE_LEN), .COEFFICIENT_LEN(COEFFICIENT_LEN))
    dut
    (
        .clk (clk),
        .rst_n (1'b1),
        .sample_i(sample_i),
        .coeff_i(coeff_i)
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
        sample_i = -8'd128; coeff_i = '0; input_valid = 1;
        @(posedge clk);
        sample_i = '0; coeff_i = '0; input_valid = 0;
    end 

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_lpf);
        $display("Hello, start of test %0t", $time);
      #100000;
        #20
        $finish;
    end
endmodule
