import sparse_mac_pkg::*;

module decoder(

    input mac_clk,
    input mac_rst,

    // Input SRAM Ready Valid Interface
    input sram_valid_i,
    output sram_ready_o,
    // Data struct from SRAM block
    input sram_data_t sram_data_i,

    // Output Comparison Ready/Valid interface
    output  decoder_valid_o,
    input   decoder_ready_i,
    // Data struct to comparison block
    output  decoder_data_t decoder_data_o
    
);
logic decoder_fifo_wren;
logic decoder_fifo_rden;
sram_data_t decoder_fifo_rdata;
logic decoder_fifo_full;
logic decoder_fifo_empty;
logic decoder_fifo_rvalid;

assign decoder_fifo_wren = sram_valid_i & sram_ready_o;
assign decoder_fifo_rden = ~decoder_fifo_empty & output_buffer_ready;

fifo_sync 
#(
    .DATA_W($bits(sram_data_t)),
    .DEPTH(DECODER_FIFO_DEPTH)
)
inp_buffer
    (
        .clk (mac_clk),
        .rstn (mac_rst),
        .i_wren(decoder_fifo_wren),
        .i_wrdata(sram_data_i),
        .o_full(decoder_fifo_full),
        .i_rden(decoder_fifo_rden),
        .o_rddata(decoder_fifo_rdata),
        .o_empty(decoder_fifo_empty)
    );

always_ff @(posedge mac_clk or negedge mac_rst) begin
    if(~mac_rst) begin
        decoder_fifo_rvalid <= 1'b0;
    end else begin
        decoder_fifo_rvalid <= decoder_fifo_rden;
    end
end

// Index calculation logic
// Input comes in with skip and value.
// Skip indicates how many zeros are inserted before the nonzero "value"
// i.e. (5,3); (4,6) -> [0,0,0,5,0,0,0,0,0,0,4]
// To resolve the index of the value location, we implement an accumulator
// The accum value is skip + 1 (where 1 indicates the location of the nonzero value)
// To make this true for the first instance, the reset value is -1 (or all 1s)
logic[INDEX_W-1:0] current_index;
logic current_index_valid;
logic[VALUE_W-1:0] current_value;
logic output_buffer_ready;
always_ff @(posedge mac_clk or negedge mac_rst) begin
    if(~mac_rst) begin
        current_index <= '1;
        current_index_valid <= 1'b0;
    end else begin
        if(decoder_fifo_rvalid) begin
            current_index_valid <= 1'b1;
            current_index <= current_index + decoder_fifo_rdata.skip + 1;
            current_value <= decoder_fifo_rdata.value;
        end else if (output_buffer_ready) begin
            current_index_valid <= 1'b0;
        end
    end
end

decoder_data_t skid_buffer_inp;
assign skid_buffer_inp.value = current_value;
assign skid_buffer_inp.index = current_index;

skid_buffer 
#(
    .DATA_W($bits(decoder_data_t))
)
out_buffer
    (
        .clk (mac_clk),
        .rstn (mac_rst),
        .valid_i(current_index_valid),
        .ready_o(output_buffer_ready),
        .data_i(skid_buffer_inp),
        .valid_o(decoder_valid_o),
        .ready_i(decoder_ready_i),
        .data_o(decoder_data_o)
    );

endmodule
