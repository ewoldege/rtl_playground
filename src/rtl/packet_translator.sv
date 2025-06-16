module packet_translator 
#(
    parameter INPUT_WIDTH = 32,
    parameter OUTPUT_WIDTH = 64
)
(
    input logic iclk,
    input logic irst,
    input logic ivalid,
    input logic isop,
    input logic ieop,
    input logic [1:0] iresidual,
    input logic [INPUT_WIDTH-1:0] idata,
    input logic ibad,

    output logic oclk,
    input  logic orst,
    output logic ovalid,
    output logic osop,
    output logic oeop,
    output logic [13:0] oplen,
    output logic [OUTPUT_WIDTH-1:0] odata,
    input  logic oready,
    output logic obad,
    output logic ohalf_word_valid,

    output logic ocpu_interrupt // Fatal error
);

typedef struct packed {
  logic sop;
  logic eop;
  logic bad;
  logic [INPUT_WIDTH-1:0] data;
} input_data_t;

typedef struct packed {
  logic sop;
  logic eop;
  logic bad;
  logic [OUTPUT_WIDTH-1:0] data;
} fifo_data_t;

typedef struct packed {
  logic [19:0] reserved;
  logic [13:0] oplen;
  logic bad;
} fifo_meta_t;

logic [13:0] pkt_byte_cntr, pkt_byte_cntr_q;
logic [13:0] init_val;
logic [2:0]  increment_val;
logic fifo_meta_wr_en, fifo_meta_wr_en_q;

// Initial is driven based off of ivalid & isop
// Addition is driven based off of ivalid & ieop
assign init_val = (ivalid & isop) ? '0 : (ivalid ? pkt_byte_cntr : '0);
assign increment_val = (ivalid & ieop) ? (~|iresidual ? 3'd4 : {1'b0, iresidual}) : (ivalid ? 3'd4 : '0);

always_ff @(posedge iclk, posedge irst) begin : proc_pkt_byte_cntr
    if(irst) begin
        pkt_byte_cntr <= '0;
        fifo_meta_wr_en <= 1'b0;
    end else begin
        pkt_byte_cntr <= init_val + increment_val;
        fifo_meta_wr_en <= ivalid & ieop;
        fifo_meta_wr_en_q <= fifo_meta_wr_en;
    end
end

logic fifo_phase0_wren;
fifo_data_t fifo_wr_data;
logic fifo_full;
logic fifo_rden;
fifo_data_t fifo_rdata;
logic fifo_rempty;
logic phase_wren_toggle, phase_wren_toggle_q;
input_data_t input_data;
input_data_t [1:0] shift_data, shift_data_q;

assign input_data.sop = isop;
assign input_data.eop = ieop;
assign input_data.data = idata;
assign input_data.bad = ibad;

// Phase values toggle between 0 and 1. 
// Start of the packet always starts with toggle value of 0.
// As new valid cycles come through, the toggle bit flips.
// When a new valid cycle comes in, and 
assign phase_wren_toggle = (isop & ivalid) ? 1'b0 : (ivalid ? ~phase_wren_toggle_q : phase_wren_toggle_q);
assign shift_data = ivalid ? {shift_data_q[0], input_data} : shift_data_q;
always_ff @(posedge iclk) begin
  phase_wren_toggle_q <= phase_wren_toggle;
  shift_data_q <= shift_data;
end

assign fifo_wren = ivalid & (phase_wren_toggle | ieop);

assign fifo_wr_data.sop = shift_data[0].sop | shift_data[1].sop;
assign fifo_wr_data.eop = shift_data[0].eop | shift_data[1].eop;
assign fifo_wr_data.data ={shift_data[1].data, shift_data[0].data};
assign fifo_wr_data.bad = (shift_data[0].bad | shift_data[1].bad);

async_fifo fifo_data
    (
        .wr_clk (iclk),
        .rst (irst),
        .wr_en(fifo_wren),
        .din(fifo_wr_data),
        .full(fifo_full),
        .rd_clk(oclk),
        .rd_en(fifo_rden),
        .dout(fifo_rdata),
        .empty(fifo_rempty)
    );

fifo_meta_t fifo_meta_wr_data;
fifo_meta_t fifo_meta_rd_data;
logic fifo_meta_full;
fifo_data_t fifo_meta_rdata;
logic fifo_meta_rden, fifo_meta_rden_q;
logic fifo_meta_rempty;
assign fifo_meta_wr_data.bad = fifo_meta_wr_en_q ? ibad : 1'b0; // TODO Should not be with _q, but vivado simulator is buggy
assign fifo_meta_wr_data.oplen = fifo_meta_wr_en_q ? pkt_byte_cntr : '0; // TODO Should not be with _q, but vivado simulator is buggy
assign fifo_meta_wr_data.reserved = '0;

async_fifo 
#(.DSIZE($bits(fifo_data_t)))
fifo_meta
    (
        .wr_clk (iclk),
        .rst (irst),
        .wr_en(fifo_meta_wr_en_q), // TODO WREN should be driven based off of ieop since wdata is clocked
        .din(fifo_meta_wr_data), // Same write data to both FIFOs
        .full(fifo_meta_full), // TODO Connect full to detect errors on incoming signal since we cannot backpressure input
        .rd_clk(oclk),
        .rd_en(fifo_meta_rden),
        .dout(fifo_meta_rd_data),
        .empty(fifo_meta_rempty)
    );

typedef enum {IDLE, DATA} state_t;
state_t curr_state, next_state;
logic pf_ready, pf_ready_q;
logic last_read_for_packet, last_read_for_packet_q;

always_ff @( posedge oclk, posedge orst ) begin
    if (orst) begin
        curr_state <= IDLE;
        pf_ready_q <= 1'b0;
    end else begin
        pf_ready_q <= pf_ready;
        curr_state <= next_state;
        fifo_meta_rden_q <= fifo_meta_rden;
    end
end

// Prefetch state machine
// IDLE state checks to see if metadata FIFO has an entry to prefetch, if it does issue read enable and advance
// DATA state indicates prefetch is ready. If we receive EOP from reading the data FIFOs, then initiate another prefetch for the next packet.
// If there is no data in the metadata FIFO to prefetch, go back to IDLE. Else issue a read enable and stay in the DATA state.
always_comb begin
  case (curr_state)
    IDLE: begin
      pf_ready = 1'b0;
      if (~fifo_meta_rempty & oready) begin
        fifo_meta_rden = 1'b1;
        next_state = DATA;
      end else begin
        fifo_meta_rden = 1'b0;
        next_state = IDLE;
      end
    end
    DATA: begin
      pf_ready = 1'b1;
      if (last_read_for_packet & ~fifo_meta_rempty) begin
        fifo_meta_rden = 1'b1;
        next_state = DATA;
      end else if (last_read_for_packet) begin
        fifo_meta_rden = 1'b0;
        next_state = IDLE;
      end else begin
        fifo_meta_rden = 1'b0;
        next_state = DATA;
      end
    end
    endcase 
end
// Not checking empty flag of FIFO because logic should handle this. Assertion in place to catch this if it happens
assign fifo_rden = pf_ready & oready & |pkt_len_remaining_q; 
logic [13:0] pkt_len_remaining, pkt_len_remaining_q;
logic half_word_valid, half_word_valid_q;

assign pkt_len_remaining = fifo_meta_rden_q ? fifo_meta_rd_data.oplen : oready ? (((pkt_len_remaining_q <= 8) ? '0 : pkt_len_remaining_q - 8)) : pkt_len_remaining_q;
assign last_read_for_packet = (pkt_len_remaining_q <= 8) & fifo_rden;
assign half_word_valid = (pkt_len_remaining_q <= 4) & fifo_rden; // Used to detect if we need to swap LSW and MSW words due to input FIFO WR data sequence


logic fifo_phase_rd_valid;
always_ff @( posedge oclk, posedge orst ) begin
    if (orst) begin
        fifo_phase_rd_valid <= 1'b0;
        last_read_for_packet_q <= 1'b0;
        pkt_len_remaining_q <= '0;
    end else begin
        pkt_len_remaining_q <= pkt_len_remaining;
        fifo_phase_rd_valid <= fifo_rden;
        last_read_for_packet_q <= last_read_for_packet;
        half_word_valid_q <= half_word_valid;
    end
end

// Error Signaling
logic err_input_wr_when_full, sticky_err_input_wr_when_full;
logic err_output_rd_when_empty, sticky_err_output_rd_when_empty;
logic err_last_read_for_packet_no_eop, sticky_err_last_read_for_packet_no_eop;
assign err_input_wr_when_full = fifo_full & fifo_wren; // FIFO filled up and input cannot be metered.
assign err_output_rd_when_empty = fifo_rempty & fifo_rden; // FIFO empty and try to read. Means fundamental failure with reading scheme.
assign err_last_read_for_packet_no_eop = last_read_for_packet_q & fifo_rdata.eop; // Last read for packet (determined by packet length) does not have EOP on output.

always_ff @( posedge iclk, posedge irst ) begin
  if(irst) begin
    sticky_err_input_wr_when_full <= 1'b0;
  end else begin
    sticky_err_input_wr_when_full <= err_input_wr_when_full | sticky_err_input_wr_when_full;
  end
end

always_ff @( posedge iclk, posedge irst ) begin
  if(irst) begin
    sticky_err_output_rd_when_empty <= 1'b0;
    sticky_err_last_read_for_packet_no_eop <= 1'b0;
  end else begin
    sticky_err_output_rd_when_empty <= err_output_rd_when_empty | sticky_err_output_rd_when_empty;
    sticky_err_last_read_for_packet_no_eop <= err_last_read_for_packet_no_eop | sticky_err_last_read_for_packet_no_eop;
  end
end

// Output assignments
assign ovalid = fifo_phase_rd_valid & ~fifo_rdata.bad;
assign osop = fifo_rdata.sop & ovalid;
assign oeop = fifo_rdata.eop & ovalid;
// Swap LSW to MSW since we are using a shift register at the beginning to shift data in at input
// If only 1 word comes in and we get an eop, we need to fix the data at some point (best spot for timing is at output)
assign odata = half_word_valid_q ? {fifo_rdata.data[31:0], 32'd0} : fifo_rdata.data;
assign oplen = fifo_meta_rd_data.oplen;
assign obad = fifo_meta_rd_data.bad;
assign ohalf_word_valid = half_word_valid_q & ovalid;

assign ocpu_interrupt = sticky_err_input_wr_when_full | sticky_err_output_rd_when_empty | sticky_err_last_read_for_packet_no_eop;

endmodule