module tb_packet_translator;
    localparam INPUT_WIDTH = 32;
    localparam OUTPUT_WIDTH = 64;
    logic iclk, oclk;
    logic irst_n, orst_n;
    logic isop, ieop, ivalid, ibad;
    logic [INPUT_WIDTH-1:0] idata;
    logic [1:0] iresidual;
    logic osop, oeop, ovalid, ohalf_word_valid, obad, oready, ocpu_interrupt;
    logic [OUTPUT_WIDTH-1:0] odata;
    logic [13:0] oplen;

    typedef struct packed {
        logic [INPUT_WIDTH-1:0]  data;
        logic         sop;
        logic         eop;
        logic [1:0]   residual;
        logic         bad;
    } pkt_struct_t;

    typedef struct packed {
        logic [OUTPUT_WIDTH-1:0]  data;
        logic         sop;
        logic         eop;
        logic [13:0]  oplen;
        logic         bad;
    } pkt_out_struct_t;

    pkt_struct_t pkt_struct, pkt_struct_input, pkt_struct_queue[$], pkt_struct_sb_queue[$];
    
    
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
        .ohalf_word_valid(ohalf_word_valid),
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
        ivalid = 1'b0;
        irst_n = 1'b1;
        orst_n = 1'b1;
        #100
        irst_n = 1'b0;
        orst_n = 1'b0;
        #100
        @(posedge iclk);
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
    logic [13:0] random_pkt_len, pkt_len_sb_queue[$];
    logic [31:0] random_wait_time;
    int bad_random_value;
    logic bad_exp;

    

    initial begin
        ready_for_data = 1;
        forever begin
            random_pkt_len = $urandom_range(64,9216);
            bad_random_value = $urandom_range(0,3);
            bad_exp = (bad_random_value == 0);
            pkt_struct.sop = 1'b1; pkt_struct.eop = 1'b0; pkt_struct.data = $urandom(); pkt_struct.residual = '0; pkt_struct.bad = 1'b0;
            pkt_struct_queue.push_back(pkt_struct);
            if(~bad_exp) begin
                pkt_struct_sb_queue.push_back(pkt_struct);
                pkt_len_sb_queue.push_back(random_pkt_len);
            end
            random_pkt_len = random_pkt_len - 4;
            @(posedge iclk);

            while (random_pkt_len > 0) begin
                pkt_struct.sop = 1'b0; 
                pkt_struct.eop = random_pkt_len <= 4; 
                pkt_struct.data = $urandom(); 
                pkt_struct.residual = (random_pkt_len >= 4) ? '0 : random_pkt_len[1:0]; 
                pkt_struct.bad = bad_exp;
                pkt_struct_queue.push_back(pkt_struct);
                if(~bad_exp) begin
                    pkt_struct_sb_queue.push_back(pkt_struct);
                end
                random_pkt_len = (random_pkt_len < 4) ? '0 : random_pkt_len - 4;
                @(posedge iclk);
            end
            random_wait_time = $urandom_range(0,32);
            while (random_wait_time > 0) begin
                @(posedge iclk);
                random_wait_time = random_wait_time - 1;
            end
            @(posedge iclk);
        end 
    end

    int oready_random_value;
    initial begin
        forever begin
            oready_random_value = $urandom_range(0,1);
            oready = (oready_random_value == 0) ? 1'b0 : 1'b1;
            @(posedge oclk);
        end
    end

    // Scoreboard
    pkt_struct_t scoreboard_expected_result0, scoreboard_expected_result1;
    pkt_out_struct_t scoreboard_expected_result, scoreboard_actual_result;
    logic [13:0] scoreboard_len_expected_result;
    logic valid_q;
    logic half_word_valid_q;
    logic check_the_value;
    logic [31:0] checked_values, passing_values, pass_induced_err_values;

    always_ff @( posedge oclk ) begin : scoreboard_ff
        valid_q <= ovalid;
        half_word_valid_q <= ohalf_word_valid;
        scoreboard_actual_result.data <= ohalf_word_valid ? {odata[63:32], 32'd0} : odata;
        scoreboard_actual_result.sop <= osop;
        scoreboard_actual_result.eop <= oeop;
        scoreboard_actual_result.oplen <= oplen;
        scoreboard_actual_result.bad <= obad;
        if (ohalf_word_valid) begin
            scoreboard_expected_result0 = pkt_struct_sb_queue.pop_front();
            scoreboard_expected_result1 = '0;
        end else if (ovalid) begin
            scoreboard_expected_result0 = pkt_struct_sb_queue.pop_front();
            scoreboard_expected_result1 = pkt_struct_sb_queue.pop_front();
        end
        if (ovalid & osop) begin
            scoreboard_len_expected_result = pkt_len_sb_queue.pop_front();
        end

    end

    assign scoreboard_expected_result.data = {scoreboard_expected_result0.data, scoreboard_expected_result1.data};
    assign scoreboard_expected_result.sop = scoreboard_expected_result0.sop | scoreboard_expected_result1.sop;
    assign scoreboard_expected_result.eop = scoreboard_expected_result0.eop | scoreboard_expected_result1.eop;
    assign scoreboard_expected_result.bad = scoreboard_expected_result0.bad | scoreboard_expected_result1.bad;
    assign scoreboard_expected_result.oplen = scoreboard_len_expected_result;

    always_ff @( posedge oclk ) begin : scoreboard
        if (orst_n) begin
            checked_values = '0;
            passing_values = '0;
        end
        else if (valid_q) begin
            check_the_value = 1;
            checked_values = checked_values + 1;
            if (scoreboard_expected_result == scoreboard_actual_result) begin
                // $display("Successful check");
                passing_values = passing_values + 1;
            end else begin
                if ((scoreboard_expected_result.oplen != scoreboard_actual_result.oplen) & (~scoreboard_expected_result.sop & ~scoreboard_actual_result.sop)) begin
                    // $display("Successful check - oplen mismatch on boundary that we dont care about");
                    passing_values = passing_values + 1;
                end else begin
                    $display("Failed addition, expected result %h, actual result %h, exp_len = %d, actual_len %d,  time = %t", scoreboard_expected_result.data, scoreboard_actual_result.data, scoreboard_expected_result.oplen, scoreboard_actual_result.oplen, $time);
                    passing_values = passing_values;
                    $error("ERROR");
                end
            end
        end else begin
            check_the_value = 0;
            checked_values = checked_values;
        end
        
    end

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_packet_translator);
        $display("Hello, start of test %0t", $time);
        #1000000;
        $display("Checked values = %d . Passing values = %d", checked_values, passing_values);
        #20
        $finish;
    end
endmodule
