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

always_ff @(posedge mac_clk) decoder_fifo_rvalid <= decoder_fifo_rden;

// Accumulator logic
logic[INDEX_W-1:0] accumulator;
logic accumulator_valid;
logic[VALUE_W-1:0] decoder_value;
always_ff @(posedge mac_clk or negedge mac_rst) begin
    if(~mac_rst) begin
        accumulator <= '1;
    end else begin
        if(decoder_fifo_rvalid) begin
            accumulator_valid <= 1'b1;
            accumulator <= accumulator + decoder_fifo_rdata.skip + 1;
            decoder_value <= decoder_fifo_rdata.value;
        end
    end
end

// Output Buffer
decoder_data_t[DECODER_OUTPUT_BUFFER_SIZE-1:0] output_buffer;
logic[$clog2(DECODER_OUTPUT_BUFFER_SIZE)-1:0] amt_filled;
logic output_handshake;
logic output_buffer_init_done;
always_ff @(posedge mac_clk or negedge mac_rst) begin
    if(~mac_rst) begin
        output_buffer_init_done <= 1'b0;
    end else begin
        if(accumulator_valid) begin
            output_buffer[0].value <= decoder_value;
            output_buffer[0].index <= accumulator;
            output_buffer[DECODER_OUTPUT_BUFFER_SIZE-1:1] <= output_buffer[DECODER_OUTPUT_BUFFER_SIZE-2:0];
        end

        if(amt_filled <= DECODER_OUTPUT_BUFFER_SIZE-1-DECODER_BUFFER_FIFO_LATENCY) begin
            decoder_fifo_rden <= 1'b1;
        end else begin
            decoder_fifo_rden <= 1'b0;
        end

        if(&amt_filled) begin
            output_buffer_init_done <= 1'b1;
        end

        if(accumulator_valid & output_handshake) begin
            // Do nothing
        end else if (accumulator_valid) begin
            amt_filled <= amt_filled + 1;
        end else if (output_handshake) begin
            amt_filled <= amt_filled - 1;
        end

    end
end

assign decoder_data_o = output_buffer[DECODER_OUTPUT_BUFFER_SIZE-1];
assign output_handshake = decoder_valid_o & decoder_ready_i;
assign decoder_valid_o = output_buffer_init_done & |amt_filled;

endmodule
