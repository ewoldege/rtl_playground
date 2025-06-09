module tb_edge_detect;
    localparam NUM_DLY = 13;
    logic clk;
    logic a;
    logic edge_detect;
    
    edge_detect
    #(.NUM_DLY(NUM_DLY))
    dut
    (
        .clk (clk),
        .rst_n (1'b1),
        .a_i(a),
        .edge_detect_o(edge_detect)
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
        a = 1;
        @(posedge clk);
        a = 0;
    end 

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_edge_detect);
        $display("Hello, start of test %0t", $time);
      #100000;
        #20
        $finish;
    end
endmodule
