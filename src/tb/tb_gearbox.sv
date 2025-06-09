module tb_gearbox;
    localparam int INPUT_DATA_W = 64;
    localparam int OUTPUT_DATA_W = 16;
    logic clk;
    logic rst_n;
    logic [INPUT_DATA_W-1:0] data_i;
    logic [OUTPUT_DATA_W-1:0] data_o;
    logic input_valid, output_valid;
    logic input_ready, output_ready;
    
    gearbox
    dut
    (
        .clk (clk),
        .rst_n (rst_n),
        .data_i(data_i),
        .valid_i(input_valid),
        .ready_i(input_ready),
        .data_o(data_o),
        .valid_o(output_valid),
        .ready_o(output_ready)
    );

    initial begin 
        clk = 0;
        forever begin
            #10 clk = ~clk;
        end 
    end

    initial begin
        #100
        rst_n = 1'b0;
        #100
        rst_n = 1'b1;
        #100
        input_ready = 1'b1;
        @(posedge clk);
        wait (output_ready) data_i = 64'hFFFFEEEEDDDDCCCC; input_valid = 1;
        @(posedge clk);
        data_i = 64'd0; input_valid = 0;
    end 

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_gearbox);
        $display("Hello, start of test %0t", $time);
      #100000;
        #20
        $finish;
    end
endmodule
