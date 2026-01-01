import sparse_mac_pkg::*;

module comparator
#(
    parameter NUM_DECODERS
)
(

    input mac_clk,
    input mac_rst,

    // Input SRAM Ready Valid Interface
    input[NUM_DECODERS-1:0] decoder_valid_i,
    output logic [NUM_DECODERS-1:0] decoder_ready_o,
    // Data struct from SRAM block
    input decoder_data_t[NUM_DECODERS-1:0] decoder_data_i,

    // Output Comparison Ready/Valid interface
    output logic mac_valid_o,
    output logic mac_finish_o,
    // Data struct to comparison block
    output  value_bus_t[NUM_DECODERS-1:0] mac_data_o
    
);

generate
    if (NUM_DECODERS != 2) begin
        initial begin
            $error("NUM_DECODERS must be 2, current value: %0d", NUM_DECODERS);
            $finish;
        end
    end
endgenerate

typedef enum {READ_BOTH_DEC, COMPARE, RD_LEFT_DEC, RD_RIGHT_DEC, MATCH, DONE} state_t;
state_t curr_state, next_state;
logic[NUM_DECODERS-1:0] decoder_accept;
decoder_data_t[NUM_DECODERS-1:0] decoder_data;
assign decoder_accept[0] = decoder_ready_o[0] & decoder_valid_i[0];
assign decoder_accept[1] = decoder_ready_o[1] & decoder_valid_i[1];

// Pre-calculate the comparison flags to save on timing
logic idx_gt, idx_lt, idx_eq;

assign idx_gt = (decoder_data[0].index > decoder_data[1].index);
assign idx_lt = (decoder_data[0].index < decoder_data[1].index);
assign idx_eq = (decoder_data[0].index == decoder_data[1].index);

always_ff @(posedge mac_clk or negedge mac_rst) begin
    if(~mac_rst) begin
        curr_state <= READ_BOTH_DEC;
    end else begin 
        curr_state <= next_state;
        if (decoder_accept[0]) begin
            decoder_data[0] <= decoder_data_i[0];
        end
        if (decoder_accept[1]) begin
            decoder_data[1] <= decoder_data_i[1];
        end
    end
end

always_comb begin
  next_state = curr_state;
  decoder_ready_o = '0;
  mac_valid_o = 1'b0;
  mac_data_o = '0;
  mac_finish_o = 1'b0;
  case (curr_state)
    READ_BOTH_DEC: begin
        decoder_ready_o = '1;
        if(&decoder_accept) begin
            next_state = COMPARE;
        end else if(decoder_accept[0]) begin
            next_state = RD_RIGHT_DEC;
        end else if(decoder_accept[1]) begin
            next_state = RD_LEFT_DEC;
        end;
    end
    RD_RIGHT_DEC: begin
      decoder_ready_o[1] = 1'b1;
      if(decoder_accept[1]) begin
        next_state = COMPARE;
      end
    end
    RD_LEFT_DEC: begin
      decoder_ready_o[0] = 1'b1;
      if(decoder_accept[0]) begin
        next_state = COMPARE;
      end
    end
    COMPARE: begin
      if (decoder_data[0].done || decoder_data[1].done) begin
        next_state = DONE;
    end else begin
        unique case ({idx_gt, idx_lt, idx_eq})
            3'b100:  next_state = RD_RIGHT_DEC; // 0 > 1
            3'b010:  next_state = RD_LEFT_DEC;  // 0 < 1
            3'b001:  next_state = MATCH;        // 0 == 1
            default: next_state = COMPARE;      // Should not happen with 'unique'
        endcase
    end
    end
    MATCH: begin
      mac_valid_o = 1'b1;
      mac_data_o = {decoder_data[1].value, decoder_data[0].value};
      next_state = READ_BOTH_DEC;
    end
    DONE: begin
      mac_finish_o = 1'b1;
    end
  endcase 
end

endmodule
