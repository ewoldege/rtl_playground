module tb_packet_translator;
    localparam INPUT_WIDTH = 32;
    localparam OUTPUT_WIDTH = 64;
    logic iclk, oclk;
    logic irst_n, orst_n;
    logic isop, ieop, ivalid, ibad;
    logic [INPUT_WIDTH-1:0] idata;
    logic [1:0] iresidual;
    logic osop, oeop, ovalid, obad, oready;
    logic [OUTPUT_WIDTH-1:0] odata;
    logic [13:0] oplen;
    
    
    packet_translator
    #(.INPUT_WIDTH(INPUT_WIDTH), .OUTPUT_WIDTH(OUTPUT_WIDTH))
    dut
    (
        .iclk (iclk),
        .irst (irst_n),
        .ivalid(ivalid),
        .isop(isop),
        .ieop(ieop),
        .iresidual(iresidual),
        .idata(idata),
        .ibad(ibad),
        .oclk (oclk),
        .orst (orst_n),
        .ovalid(ovalid),
        .osop(osop),
        .oeop(oeop),
        .oplen(oplen),
        .odata(odata),
        .obad(obad),
        .oready(oready)
    );

    initial begin 
        iclk = 0;
        forever begin
            #1.6 iclk = ~iclk; // 312.5MHz
        end 
    end

    initial begin 
        oclk = 0;
        #0.5
        forever begin
            #2 oclk = ~oclk; // 250MHz
        end 
    end

    initial begin
        #100
        irst_n = 1'b1;
        orst_n = 1'b1;
        #100
        irst_n = 1'b0;
        orst_n = 1'b0;
        #100
        @(posedge iclk);
        oready = 1'b1;
        @(posedge iclk);
        isop = 1'b1; ivalid = 1'b1; idata = 32'hBADE0856; ieop = 1'b1; iresidual = '0;
        @(posedge iclk);
        isop = 1'b0; ivalid = 1'b0; idata = '0; ieop = 1'b0; iresidual = '0;
    end 

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_packet_translator);
        $display("Hello, start of test %0t", $time);
      #100000;
        #20
        $finish;
    end
endmodule
