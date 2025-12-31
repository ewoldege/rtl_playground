module skid_buffer
#(
    parameter DATA_W;
)
(
    input clk,
    input rstn,

    // Input SRAM Ready Valid Interface
    input valid_i,
    output ready_o,
    // Data struct from SRAM block
    input logic[DATA_W-1:0] data_i,

    // Output Comparison Ready/Valid interface
    output  valid_o,
    input   ready_i,
    // Data struct to comparison block
    output logic[DATA_W-1:0] data_o
    
);

logic full;
logic [DATA_W-1:0] data_reg;
logic [DATA_W-1:0] main_reg;
logic main_valid;

assign ready_o = ~full;
assign valid_o = main_valid; 
assign data_o = main_reg;

always_ff @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        full <= 1'b0;
        main_valid <= 1'b0;
    end else begin
        if(valid_i & ready_o & ~ready_i) begin
            full <= 1'b1;
            data_reg <= data_i;
        end else (ready_i) begin
            full <= 1'b0;
            main_valid <= full ? 1'b1 : valid_i;
            main_reg <= full ? data_reg : data_i;
        end 
    end
end

endmodule
