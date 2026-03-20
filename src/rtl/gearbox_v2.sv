`timescale 1ns/1ps

module gearbox_v2
#(
    parameter int IN_W = 32,
    parameter int OUT_W = 48
)
(
    input  logic                                      clk,
    input  logic                                      rst_n,
    output logic                                      ready_o,
    input  logic                                      valid_i,
    input  logic [IN_W-1:0]                           data_i,

    input  logic                                      ready_i,
    output logic                                      valid_o,
    output logic [OUT_W-1:0]                          data_o
);

    localparam INT_BUS_W = (IN_W > OUT_W) ? 2*IN_W : 2*OUT_W;
    localparam INT_BUS_CNTR_W = $clog2(INT_BUS_W+1);

    logic [INT_BUS_W-1:0] int_bus, int_bus_masked, int_bus_q;
    logic [INT_BUS_CNTR_W-1:0] cntr;
    logic up, down;
    logic [INT_BUS_W-1:0] mask_pre_shift, mask_post_shift;

    assign up = ready_o && valid_i;
    assign down = ready_i && valid_o;

    always_comb begin
        int_bus_masked = int_bus_q;
        mask_pre_shift = '0;
        mask_post_shift = '0;
        if(up) begin
            mask_pre_shift = data_i;
            mask_post_shift = mask_pre_shift << (INT_BUS_W - IN_W - cntr);
            int_bus_masked = int_bus_q | mask_post_shift; // Bitwise Mask
        end
        if(down) begin
            int_bus = int_bus_masked << OUT_W;
        end else begin
            int_bus = int_bus_masked;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            cntr <= '0;
            int_bus_q <= '0;
        end else begin
            int_bus_q <= int_bus;
            if(up && down) begin
                cntr <= cntr + IN_W - OUT_W;
            end else if (up) begin
                cntr <= cntr + IN_W;
            end else if (down) begin
                cntr <= cntr - OUT_W;
            end
        end
    end

    assign ready_o = (cntr <= IN_W);
    assign valid_o = (cntr >= OUT_W);
    assign data_o  = int_bus_q[INT_BUS_W-1:INT_BUS_W-OUT_W];

endmodule
