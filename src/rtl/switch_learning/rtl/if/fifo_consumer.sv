interface fifo_consumer #(parameter DATA_W = 32) (input logic clk, input logic rst_n);
    logic valid;
    logic ready;
    logic [DATA_W-1:0] data;

    modport source(
        input clk,
        input rst_n,
        output valid,
        input ready,
        output data
    );

    modport sink(
        input clk,
        input rst_n,
        input valid,
        output ready,
        input data
    );
endinterface