module gearbox 
#(
    parameter int INPUT_DATA_W = 64,
    parameter int OUTPUT_DATA_W = 16
)
(
    input clk,
    input rst_n,

    input logic [INPUT_DATA_W-1:0] data_i,
    input logic valid_i,
    input logic ready_i,
    output logic [OUTPUT_DATA_W-1:0] data_o,
    output logic valid_o,
    output logic ready_o
);
/* verilator lint_off REALCVT */
localparam int NUM_SHIFT_CYCLES = $ceil(INPUT_DATA_W/OUTPUT_DATA_W);
/* verilator lint_on REALCVT */
typedef enum {IDLE, DATA} state_t;
state_t curr_state, next_state;

logic load;
logic valid, ready;
logic output_handshake;
logic [$clog2(NUM_SHIFT_CYCLES)-1:0] count, count_q;
logic [INPUT_DATA_W-1:0] data_sr, data_sr_q;
assign load = valid_i & ready_o;
assign output_handshake = ready_i & valid_o;

always_ff @(posedge clk) begin
    if(~rst_n) begin
        curr_state <= IDLE;
    end else begin 
        curr_state <= next_state;
        count_q <= count;
        data_sr_q <= data_sr;
    end
end

always_comb begin
  case (curr_state)
    IDLE: begin // Ready to accept new data. Output data is invalid in this state
        if (load) begin
            next_state = DATA;
        end else begin
            next_state = IDLE;
        end
        count = 'd0;
        valid = 0;
        ready = 1'b1;
    end
    DATA: begin // Processing data, do not accept new data. Output processed data
        if(count_q == NUM_SHIFT_CYCLES-1 & ready_i) begin
            next_state = IDLE;
        end else begin
            next_state = DATA;
        end
        if (ready_i) begin 
           count = count_q + 1;
        end else begin
           count = count_q;
        end
        valid = 1'b1;
        ready = 1'b0;
    end
    endcase 
end

assign data_sr = load ? data_i : (output_handshake ? data_sr_q << OUTPUT_DATA_W : data_sr_q);
assign valid_o = valid;
assign ready_o = ready;
assign data_o = data_sr_q[(INPUT_DATA_W-1):(INPUT_DATA_W-OUTPUT_DATA_W)]; // Top-most Output data width segment is output

endmodule