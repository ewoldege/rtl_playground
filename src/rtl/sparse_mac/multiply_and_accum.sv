import sparse_mac_pkg::*;

module multiply_and_accum
#(
    parameter NUM_DECODERS
)
(

    input mac_clk,
    input mac_rst,

    // Input SRAM Ready Valid Interface
    input comparator_valid_i,
    input comparator_done_i,
    // Data struct from SRAM block
    input value_bus_t[NUM_DECODERS-1:0] comparator_data_i,

    // Output Comparison Ready/Valid interface
    output mac_valid_o,
    // Data struct to comparison block
    output [ACCUM_W-1:0] mac_data_o
    
);

generate
    if (NUM_DECODERS != 2) begin
        initial begin
            $error("NUM_DECODERS must be 2, current value: %0d", NUM_DECODERS);
            $finish;
        end
    end
endgenerate

logic[2*VALUE_W-1:0] multiply_value;
logic multiply_valid;
// Multiplication process
always_ff @(posedge mac_clk or negedge mac_rst) begin
    if(~mac_rst) begin
        multiply_valid <= 1'b0;
    end else begin 
        if(comparator_valid_i) begin
            multiply_value <= comparator_data_i[1] * comparator_data_i[0];
            multiply_valid <= comparator_valid_i;
        end else begin
            multiply_valid <= 1'b0;
        end
    end
end
logic[2*2*VALUE_W-1:0] accum_value;
// Accumulate process
always_ff @(posedge mac_clk or negedge mac_rst) begin
    if(~mac_rst) begin
        accum_value <= '0; // Need to reset accumulator value since it is a feedback operation
    end else begin 
        if(multiply_valid) begin
            accum_value <= accum_value + multiply_value;
        end
    end
end

// Done indicates that the decoder received a termination input from one of its inputs.
// If the comparison block sees this indication, that means that the decoder it was fetching from
// had no more valid inputs. This means that we are done with our MAC process.
assign mac_valid_o = comparator_done_i;
assign mac_data_o = accum_value;

endmodule
