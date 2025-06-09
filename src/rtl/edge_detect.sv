module edge_detect 
#(
    parameter NUM_DLY = 13
)
(
    input clk,
    input rst_n,

    input logic a_i,
    output logic edge_detect_o

);

localparam CNTR_WIDTH = $clog2(NUM_DLY);
logic[CNTR_WIDTH-1:0] dly_cntr;
logic a_q, a_2q;
logic tc;
logic edge_detect;
logic cnt_en;

always_ff @( posedge clk ) begin
    if(~rst_n) begin

    end else begin
        a_2q <= a_q;
        a_q <= a_i;
        dly_cntr <= edge_detect ? '0 : cnt_en ? (dly_cntr + 1) : dly_cntr;
        cnt_en <= edge_detect ? 1'b1 : (tc ? 1'b0 : cnt_en);
    end
end
assign tc = (dly_cntr == NUM_DLY);
assign edge_detect = ~a_2q & a_i;
assign edge_detect_o = tc & cnt_en;

endmodule