module async_fifo_v2
#(
    parameter int FIFO_DEPTH = 32,
    parameter int FIFO_WIDTH = 64
)
(
    input wclk,
    input wrst_n,
    input rclk,
    input rrst_n,
    
    input [FIFO_WIDTH-1:0] wdata,
    input wren,
    output full,

    input rden,
    output logic [FIFO_WIDTH-1:0] rdata,
    output empty
);
    localparam int FIFO_DEPTH_W = $clog2(FIFO_DEPTH);

    function automatic logic[FIFO_DEPTH_W:0] standard_to_gray(
        input logic[FIFO_DEPTH_W:0] standard
    );
        logic [FIFO_DEPTH_W:0] gray;
        for(int i = 0; i < FIFO_DEPTH_W; i++) begin
            gray[i] = standard[i] ^ standard[i+1];
        end
        gray[FIFO_DEPTH_W] = standard[FIFO_DEPTH_W];
        return gray;
    endfunction;

    function automatic logic[FIFO_DEPTH_W:0] gray_to_standard(
        input logic[FIFO_DEPTH_W:0] gray
    );
        logic [FIFO_DEPTH_W:0] standard;
        standard[FIFO_DEPTH_W] = gray[FIFO_DEPTH_W];
        for(int i = FIFO_DEPTH_W-1; i >= 0; i--) begin
            standard[i] = standard[i+1] ^ gray[i];
        end
        return standard;
    endfunction;
    
    logic [FIFO_DEPTH-1:0][FIFO_WIDTH-1:0] mem;
    logic [FIFO_DEPTH_W:0] wptr_next, wptr_inc, wptr, wptr_g, rptr_next, rptr, rptr_g, wptr_gr1, wptr_gr2, rptr_gw1, rptr_gw2;
    logic [FIFO_DEPTH_W:0] rptr_w, wptr_r;

    assign wptr_next = (wren && ~full) ? wptr_inc : wptr;
    assign wptr_inc = ((wptr[FIFO_DEPTH_W-1:0] == FIFO_DEPTH-1) ? {~wptr[FIFO_DEPTH_W], {FIFO_DEPTH_W{1'b0}}} : wptr + 1);
    
    // Write Process
    always_ff @(posedge wclk or negedge wrst_n) begin
        if(~wrst_n) begin
            wptr <= '0;
            wptr_g <= '0;
        end else begin
            if(wren && ~full) begin
                mem[wptr[FIFO_DEPTH_W-1:0]] <= wdata;
                wptr <= wptr_next;
            end
            wptr_g <= standard_to_gray(wptr_next);
        end
    end

    assign rptr_next = (rden && ~empty) ? ((rptr[FIFO_DEPTH_W-1:0] == FIFO_DEPTH-1) ? {~rptr[FIFO_DEPTH_W], {FIFO_DEPTH_W{1'b0}}} : rptr + 1) : rptr;

    // Read Process
    always_ff @(posedge rclk or negedge rrst_n) begin
        if(~rrst_n) begin
            rptr <= '0;
            rptr_g <= '0;
        end else begin
            if(rden && ~empty) begin
                rptr <= rptr_next;
                rdata <= mem[rptr[FIFO_DEPTH_W-1:0]];
            end
            rptr_g <= standard_to_gray(rptr_next);
        end
    end

    // Full Logic
    always_ff @(posedge wclk or negedge wrst_n) begin
        if(~wrst_n) begin
            rptr_gw1 <= '0;
            rptr_gw2 <= '0;
        end else begin
            rptr_gw1 <= rptr_g;
            rptr_gw2 <= rptr_gw1;
        end
    end

    assign rptr_w = gray_to_standard(rptr_gw2);
    assign full = (rptr_w[FIFO_DEPTH_W] ^ wptr_inc[FIFO_DEPTH_W]) & (rptr_w[FIFO_DEPTH_W-1:0] == wptr_inc[FIFO_DEPTH_W-1:0]);

    // Empty Logic
    always_ff @(posedge rclk or negedge rrst_n) begin
        if(~rrst_n) begin
            wptr_gr1 <= '0;
            wptr_gr2 <= '0;
        end else begin
            wptr_gr1 <= wptr_g;
            wptr_gr2 <= wptr_gr1;
        end
    end

    assign wptr_r = gray_to_standard(wptr_gr2);
    assign empty = wptr_r[FIFO_DEPTH_W:0] == rptr[FIFO_DEPTH_W:0];

endmodule;