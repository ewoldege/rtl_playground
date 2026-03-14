//------------------------------------------------------------------------------
// File: ingress_parser.sv
// Description:
//   Proposed top-level parser module interface for a pipelined ingress parser.
//
// Notes:
//   - This module declaration intentionally contains only ports.
//   - No parser implementation logic is generated here.
//   - The interface is shaped to sit between a header-slice producer and a
//     downstream match-action pipeline.
//------------------------------------------------------------------------------

module ingress_parser
  import ingress_parser_pkg::*;
(
  //----------------------------------------------------------------------------
  // Clock / reset
  //----------------------------------------------------------------------------

  input  logic                      clk,            // Core parser clock
  input  logic                      rst_n,          // Active-low synchronous or async reset per implementation style

  //----------------------------------------------------------------------------
  // Packet header slice input
  //
  // The parser consumes one 1024-bit slice containing the first 128 bytes of
  // packet header data. This is assumed to be presented after RX MAC/framing.
  //----------------------------------------------------------------------------

  input  logic                      valid_i,        // Input beat valid; indicates data_i/keep_i/control are meaningful
  input  logic                      sop_i,          // Start-of-packet marker for the header slice
  input  logic                      eop_i,          // End-of-packet marker if packet ends in this beat
  input  logic [PARSER_DATA_W-1:0]  data_i,         // First 128 bytes of packet header data
  input  logic [PARSER_KEEP_W-1:0]  keep_i,         // Byte-valid mask; 1 bit per byte in data_i for truncation/coverage checks

  //----------------------------------------------------------------------------
  // Ingress sideband attributes
  //----------------------------------------------------------------------------

  input  logic [INGRESS_PORT_W-1:0] ingress_port_i, // Source ingress port used for policy, forwarding domain, and telemetry
  input  logic [PKT_LEN_W-1:0]      pkt_len_i,      // Full packet length for sanity checks and downstream policy

  //----------------------------------------------------------------------------
  // Parsed metadata output
  //----------------------------------------------------------------------------

  output logic                      valid_o,        // Output metadata valid; aligns with parser_meta_o and status outputs
  output parser_meta_t              parser_meta_o,  // Normalized parser metadata for downstream match-action stages
  output logic                      parse_error_o   // Aggregated parse error indication for drop/punt/error handling
  // output logic                   drop_o          // Optional alternative to parse_error_o if parser directly signals drop
);

endmodule : ingress_parser
