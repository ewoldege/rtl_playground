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

    input  logic oclk,
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
  logic [19:0] reserved;
  logic [13:0] oplen;
  logic bad;
} fifo_meta_t;

logic [13:0] pkt_byte_cntr;
logic [13:0] init_val;
logic [2:0]  increment_val;
logic fifo_meta_wr_en, fifo_meta_wr_en_q;



logic [OUTPUT_WIDTH-1:0] fifo_wr_data;
logic fifo_full;
logic fifo_rden, fifo_rd_en_q;
logic [OUTPUT_WIDTH-1:0] fifo_rdata;
logic fifo_rempty;
logic phase_wren_toggle, phase_wren_toggle_q;
logic [OUTPUT_WIDTH-1:0] shift_data, shift_data_q;
logic bad_2q, bad_q;

// Phase values toggle between 0 and 1. 
// Start of the packet always starts with toggle value of 0.
// As new valid cycles come through, the toggle bit flips.
// When a new valid cycle comes in, and 
assign phase_wren_toggle = (isop & ivalid) ? 1'b0 : (ivalid ? ~phase_wren_toggle_q : phase_wren_toggle_q);
assign shift_data = ivalid ? {shift_data_q[INPUT_WIDTH-1:0], idata} : shift_data_q;
always_ff @(posedge iclk) begin
  phase_wren_toggle_q <= phase_wren_toggle;
  shift_data_q <= shift_data;
  bad_q <= ibad;
  bad_2q <= bad_q;
end

assign fifo_wren = ivalid & (phase_wren_toggle | ieop);
assign fifo_wr_data = shift_data;

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
logic fifo_meta_rden;
logic fifo_meta_rempty;

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

assign fifo_meta_wr_data.bad = bad_2q;
assign fifo_meta_wr_data.oplen = pkt_byte_cntr;
assign fifo_meta_wr_data.reserved = '0;

async_fifo fifo_meta
    (
        .wr_clk (iclk),
        .rst (irst),
        .wr_en(fifo_meta_wr_en_q), 
        .din(fifo_meta_wr_data), 
        .full(fifo_meta_full),
        .rd_clk(oclk),
        .rd_en(fifo_meta_rden),
        .dout(fifo_meta_rd_data),
        .empty(fifo_meta_rempty)
    );

typedef enum {IDLE, META, SOP, DATA} state_t;
state_t curr_state, next_state;
logic sop, sop_q;
logic eop, eop_q;
logic meta_bad, meta_bad_q;
// Not checking empty flag of FIFO because logic should handle this. Assertion in place to catch this if it happens
logic [13:0] pkt_len_remaining, pkt_len_remaining_q;
logic [13:0] plen, plen_q;

always_ff @( posedge oclk, posedge orst ) begin
    if (orst) begin
        curr_state <= IDLE;
    end else begin
        curr_state <= next_state;
    end
end

// Prefetch state machine
// IDLE state checks to see if metadata FIFO has an entry to prefetch, if it does issue read enable and advance
// DATA state indicates prefetch is ready. If we receive EOP from reading the data FIFOs, then initiate another prefetch for the next packet.
// If there is no data in the metadata FIFO to prefetch, go back to IDLE. Else issue a read enable and stay in the DATA state.
always_comb begin
  sop = 1'b0;
  eop = 1'b0;
  fifo_meta_rden = 1'b0;
  fifo_rden = 1'b0;
  pkt_len_remaining = pkt_len_remaining_q;
  meta_bad = meta_bad_q;
  plen = '0;
  next_state = curr_state;
  case (curr_state)
    IDLE: begin
      if (~fifo_meta_rempty & oready) begin
        fifo_meta_rden = 1'b1;
        next_state = META;
      end else begin
        fifo_meta_rden = 1'b0;
        next_state = IDLE;
      end
    end
    META: begin
      pkt_len_remaining = fifo_meta_rd_data.oplen;
      meta_bad = fifo_meta_rd_data.bad;
      next_state = SOP;
    end
    SOP: begin
      if (oready & |pkt_len_remaining_q) begin
        fifo_rden = 1'b1;
        plen = pkt_len_remaining_q;
        pkt_len_remaining = pkt_len_remaining_q - 8;
        sop = 1'b1;
        next_state = DATA;
      end else begin
        fifo_rden = 1'b0;
        pkt_len_remaining = pkt_len_remaining_q;
        sop = 1'b0;
        next_state = SOP;
      end
    end
    DATA: begin
      if (oready) begin
        if(pkt_len_remaining_q <= 8) begin
          pkt_len_remaining = '0;
          eop = 1'b1;
          fifo_rden = 1'b1;
          if(~fifo_meta_rempty) begin
            fifo_meta_rden = 1'b1;
            next_state = META;
          end else begin
            fifo_meta_rden = 1'b0;
            next_state = IDLE;
          end
        end else begin
          fifo_rden = 1'b1;
          pkt_len_remaining = pkt_len_remaining_q - 8;
          next_state = DATA;
        end
      end else begin
        fifo_rden = 1'b0;
        next_state = DATA;
      end
    end
    endcase 
end

logic half_word_valid, half_word_valid_q;
assign half_word_valid = (pkt_len_remaining_q <= 4) & fifo_rden; // Used to detect if we need to swap LSW and MSW words due to input FIFO WR data sequence

always_ff @( posedge oclk, posedge orst ) begin
    if (orst) begin
        fifo_rd_en_q <= 1'b0;
        pkt_len_remaining_q <= '0;
        meta_bad_q <= 1'b0;
    end else begin
        pkt_len_remaining_q <= pkt_len_remaining;
        fifo_rd_en_q <= fifo_rden;
        half_word_valid_q <= half_word_valid;
        meta_bad_q <= meta_bad;
        sop_q <= sop;
        eop_q <= eop;
        plen_q <= plen;
    end
end

// Error Signaling
logic err_input_wr_when_full, sticky_err_input_wr_when_full;
logic err_output_rd_when_empty, sticky_err_output_rd_when_empty;
assign err_input_wr_when_full = fifo_full & fifo_wren; // FIFO filled up and input cannot be metered.
assign err_output_rd_when_empty = fifo_rempty & fifo_rden; // FIFO empty and try to read. Means fundamental failure with reading scheme.

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
  end else begin
    sticky_err_output_rd_when_empty <= err_output_rd_when_empty | sticky_err_output_rd_when_empty;
  end
end

// Output assignments
assign ovalid = fifo_rd_en_q & ~meta_bad_q;
assign osop = sop_q & ovalid;
assign oeop = eop_q & ovalid;
// Swap LSW to MSW since we are using a shift register at the beginning to shift data in at input
// If only 1 word comes in and we get an eop, we need to fix the data at some point (best spot for timing is at output)
assign odata = half_word_valid_q ? {fifo_rdata[31:0], 32'd0} : fifo_rdata;
assign oplen = plen_q;
assign obad = fifo_meta_rd_data.bad;
assign ohalf_word_valid = half_word_valid_q & ovalid;

assign ocpu_interrupt = sticky_err_input_wr_when_full | sticky_err_output_rd_when_empty;

endmodule