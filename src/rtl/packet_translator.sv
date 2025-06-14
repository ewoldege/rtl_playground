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

    output logic ocpu_interrupt // Fatal error
);

typedef struct packed {
  logic sop;
  logic eop;
  logic bad;
  logic [31:0] data;
} fifo_data_t;

typedef struct packed {
  logic [13:0] oplen;
  logic bad;
} fifo_meta_t;

logic [13:0] pkt_byte_cntr, pkt_byte_cntr_q;
logic [13:0] init_val;
logic [2:0]  increment_val;

// Initial is driven based off of ivalid & isop
// Addition is driven based off of ivalid & ieop
assign init_val = (ivalid & isop) ? '0 : (ivalid ? pkt_byte_cntr : '0);
assign increment_val = (ivalid & ieop) ? (~&iresidual ? 3'd4 : iresidual) : (ivalid ? 3'd4 : '0);

always_ff @(posedge iclk, posedge irst) begin : proc_pkt_byte_cntr
    if(irst) begin
        pkt_byte_cntr <= '0;
    end else begin
        pkt_byte_cntr <= init_val + increment_val;
    end
end

logic fifo_phase0_wren;
fifo_data_t fifo_phase_data;
logic fifo_phase0_full;
logic fifo_phase0_rden;
fifo_data_t fifo_phase0_rdata;
logic fifo_phase0_rempty;
logic phase_wren_toggle, phase_wren_toggle_q;

// Phase values toggle between 0 and 1. 
// Start of the packet always starts with toggle value of 0.
// As new valid cycles come through, the toggle bit flips.
// Phase 0 FIFO wren is enabled when toggle == 0.
// Phase 1 FIFO wren is enabled when toggle == 1.
assign phase_wren_toggle = (isop & ivalid) ? 1'b0 : (ivalid ? ~phase_wren_toggle_q : phase_wren_toggle_q);
always_ff @(posedge iclk) phase_wren_toggle_q <= phase_wren_toggle;

assign fifo_phase0_wren = ivalid & ~phase_wren_toggle;
// Common FIFO Write Data
assign fifo_phase_data.sop = isop;
assign fifo_phase_data.eop = ieop;
assign fifo_phase_data.data = idata;
assign fifo_phase_data.bad = ibad;

// // Common FIFO RD Enable
// assign fifo_phase_rden = oready & ~fifo_phase0_rempty & ~fifo_phase1_rempty & pf_ready;

async_fifo 
#(.DSIZE($bits(fifo_data_t)))
fifo_phase0
    (
        .wclk (iclk),
        .wrst_n (~irst),
        .winc(fifo_phase0_wren),
        .wdata(fifo_phase_data), // Same write data to both FIFOs
        .wfull(fifo_phase0_full), // TODO Connect full to detect errors on incoming signal since we cannot backpressure input
        .rclk(oclk),
        .rrst_n (~orst),
        .rinc(fifo_phase0_rden),
        .rdata(fifo_phase0_rdata),
        .rempty(fifo_phase0_rempty)
    );

logic fifo_phase1_wren;
logic fifo_phase1_full;
logic fifo_phase1_rden;
fifo_data_t fifo_phase1_rdata;
logic fifo_phase1_rempty;

assign fifo_phase1_wren = ivalid & phase_wren_toggle;

async_fifo 
#(.DSIZE($bits(fifo_data_t)))
fifo_phase1
    (
        .wclk (iclk),
        .wrst_n (~irst),
        .winc(fifo_phase1_wren),
        .wdata(fifo_phase_data), // Same write data to both FIFOs
        .wfull(fifo_phase1_full), // TODO Connect full to detect errors on incoming signal since we cannot backpressure input
        .rclk(oclk),
        .rrst_n (~orst),
        .rinc(fifo_phase1_rden),
        .rdata(fifo_phase1_rdata),
        .rempty(fifo_phase1_rempty)
    );

fifo_meta_t fifo_meta_wr_data;
fifo_meta_t fifo_meta_rd_data;
logic fifo_meta_full;
fifo_data_t fifo_meta_rdata;
logic fifo_meta_rden, fifo_meta_rden_q;
logic fifo_meta_rempty;
assign fifo_meta_wr_data.bad = ieop ? ibad : 1'b0;
assign fifo_meta_wr_data.oplen = ieop ? pkt_byte_cntr : '0;

async_fifo 
#(.DSIZE($bits(fifo_data_t)))
fifo_meta
    (
        .wclk (iclk),
        .wrst_n (~irst),
        .winc(ieop), // TODO WREN should be driven based off of ieop since wdata is clocked
        .wdata(fifo_meta_wr_data), // Same write data to both FIFOs
        .wfull(fifo_meta_full), // TODO Connect full to detect errors on incoming signal since we cannot backpressure input
        .rclk(oclk),
        .rrst_n (~orst),
        .rinc(fifo_meta_rden),
        .rdata(fifo_meta_rd_data),
        .rempty(fifo_meta_rempty)
    );

typedef enum {IDLE, DATA} state_t;
state_t curr_state, next_state;
logic pf_ready;

always_ff @( posedge oclk, posedge orst ) begin
    if (orst) begin
        curr_state <= IDLE;
    end else begin
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
      if (oeop & ~fifo_meta_rempty & oready) begin
        fifo_meta_rden = 1'b1;
        next_state = DATA;
      end else if (oeop) begin
        fifo_meta_rden = 1'b0;
        next_state = IDLE;
      end else begin
        fifo_meta_rden = 1'b0;
        next_state = DATA;
      end
    end
    endcase 
end

logic [13:0] pkt_len_remaining, pkt_len_remaining_q;

assign pkt_len_remaining = fifo_meta_rden_q ? fifo_meta_rd_data.oplen : oready ? (((pkt_len_remaining_q <= 8) ? '0 : pkt_len_remaining_q - 8)) : pkt_len_remaining_q;
assign fifo_phase0_rden = |pkt_len_remaining_q & oready; // If there is any data, read FIFO phase 0
assign fifo_phase1_rden = pkt_len_remaining_q > 4 & oready; // If there is more than 4 bytes remaining, read FIFO phase 1

logic fifo_phase_rd_valid;
always_ff @( posedge oclk, posedge orst ) begin
    if (orst) begin
       pkt_len_remaining_q <= '0; 
    end else begin
       pkt_len_remaining_q <= pkt_len_remaining;
       fifo_phase_rd_valid <= fifo_phase0_rden; // FIFO Phase 0 will always be read on any given read cycle.
    end
end

assign ovalid = fifo_phase_rd_valid;
assign osop = fifo_phase0_rdata.sop | fifo_phase1_rdata.sop;
assign oeop = fifo_phase0_rdata.eop | fifo_phase1_rdata.eop;
assign odata = {fifo_phase0_rdata.data, fifo_phase1_rdata.data};
assign oplen = fifo_meta_rd_data.oplen;
assign obad = fifo_meta_rd_data.bad;

endmodule