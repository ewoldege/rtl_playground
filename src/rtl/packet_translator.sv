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
    output logic [OUTPUT_WIDTH-1:0]odata,
    input  logic oready,
    output logic obad
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
logic fifo_phase_rden;
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

// Common FIFO RD Enable
assign fifo_phase_rden = oready & ~fifo_phase0_rempty & ~fifo_phase1_rempty;

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
        .rinc(fifo_phase_rden),
        .rdata(fifo_phase0_rdata),
        .rempty(fifo_phase0_rempty)
    );

logic fifo_phase1_wren;
logic fifo_phase1_full;
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
        .rinc(fifo_phase_rden),
        .rdata(fifo_phase1_rdata),
        .rempty(fifo_phase1_rempty)
    );

fifo_meta_t fifo_meta_wr_data;
fifo_meta_t fifo_meta_rd_data;
logic fifo_meta_full;
fifo_data_t fifo_meta_rdata;
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
        .rinc(fifo_phase_rden),
        .rdata(fifo_meta_rd_data),
        .rempty(fifo_meta_rempty)
    );

logic fifo_phase_rd_valid;

always_ff @( posedge oclk ) begin
    fifo_phase_rd_valid <= fifo_phase_rden;
end

assign ovalid = fifo_phase_rd_valid;
assign osop = fifo_phase0_rdata.sop | fifo_phase1_rdata.sop;
assign oeop = fifo_phase0_rdata.eop | fifo_phase1_rdata.eop;
assign odata = {fifo_phase0_rdata.data, fifo_phase1_rdata.data};

endmodule