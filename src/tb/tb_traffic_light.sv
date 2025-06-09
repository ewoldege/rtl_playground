module tb_traffic_light;
    logic clk;
    logic rst_n;
    logic ns_g, ns_y, ns_r;
    logic ew_g, ew_y, ew_r;
    
    traffic_light
    dut
    (
        .clk (clk),
        .rst_n (rst_n),
        .ns_g_o(ns_g),
        .ns_y_o(ns_y),
        .ns_r_o(ns_r),
        .ew_g_o(ew_g),
        .ew_y_o(ew_y),
        .ew_r_o(ew_r)
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
    end 

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_traffic_light);
        $display("Hello, start of test %0t", $time);
      #100000;
        #20
        $finish;
    end
endmodule
