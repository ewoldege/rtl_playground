module tb_packet_translator;
    localparam INPUT_WIDTH = 32;
    localparam OUTPUT_WIDTH = 64;
    logic iclk, oclk;
    logic irst_n, orst_n;
    logic isop, ieop, ivalid, ibad;
    logic [INPUT_WIDTH-1:0] idata;
    logic [1:0] iresidual;
    logic osop, oeop, ovalid, obad, oready, ocpu_interrupt;
    logic [OUTPUT_WIDTH-1:0] odata;
    logic [13:0] oplen;

    typedef struct packed {
        logic [31:0]  data;
        logic         sop;
        logic         eop;
        logic         residual;
        logic         bad;
    } pkt_struct_t;

    pkt_struct_t pkt_struct, pkt_struct_input, pkt_struct_queue[$];
    
    
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
        .oready(oready),
        .ocpu_interrupt (ocpu_interrupt)
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
        forever begin
            if (pkt_struct_queue.size() > 0) begin
                pkt_struct_input = pkt_struct_queue.pop_front();
                isop = pkt_struct_input.sop; ivalid = 1'b1; idata = pkt_struct_input.data; ieop = pkt_struct_input.eop; iresidual = pkt_struct_input.residual; ibad = pkt_struct_input.bad;
            end else begin
                isop = 1'b0; ivalid = 1'b0; idata = '0; ieop = 1'b0; iresidual = '0; ibad = 1'b0;
            end
            @(posedge iclk);
        end
    end

    logic [31:0] tb_data, tb_datb;
    logic [31:0] expected_result;
    logic [31:0]  random_err_bus;
    logic ready_for_data;
    logic [13:0] random_pkt_len;
    logic [31:0] random_wait_time;

    

    initial begin
        ready_for_data = 1;
        forever begin
            random_pkt_len = $urandom_range(64,9216);
            pkt_struct.sop = 1'b1; pkt_struct.eop = 1'b0; pkt_struct.data = $urandom(); pkt_struct.residual = '0; pkt_struct.bad = 1'b0;
            pkt_struct_queue.push_back(pkt_struct);
            random_pkt_len = random_pkt_len - 4;

            while (random_pkt_len > 0) begin
                pkt_struct.sop = 1'b0; pkt_struct.eop = random_pkt_len <= 4; pkt_struct.data = $urandom(); pkt_struct.residual = (random_pkt_len >= 4) ? '0 : random_pkt_len[1:0]; pkt_struct.bad = 1'b0;
                pkt_struct_queue.push_back(pkt_struct);
                random_pkt_len = (random_pkt_len < 4) ? '0 : random_pkt_len - 4;
            end
            random_wait_time = $urandom_range(1,32);
            while (random_wait_time > 0) begin
                @(posedge iclk);
                random_wait_time = random_wait_time - 1;
            end
            @(posedge iclk);
        end 
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
