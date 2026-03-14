//------------------------------------------------------------------------------
// File: ingress_parser_pkg.sv
// Description:
//   Package containing parser-wide constants, protocol enums, parser context,
//   and normalized metadata definitions for a bounded ingress Ethernet/VXLAN
//   parser feeding a downstream match-action pipeline.
//
// Notes:
//   - This package intentionally contains only type and constant definitions.
//   - No parser logic is implemented here.
//   - Types are structured to support a pipelined parser carrying a context
//     record stage-to-stage and emitting normalized metadata at the output.
//------------------------------------------------------------------------------

package ingress_parser_pkg;

  //----------------------------------------------------------------------------
  // Parser-wide limits and architectural constants
  //----------------------------------------------------------------------------

  // Width of the parser header slice captured from the packet front.
  // The parser operates on the first 128 bytes only.
  localparam int unsigned PARSER_DATA_W            = 1024;
  localparam int unsigned PARSER_KEEP_W            = 128;
  localparam int unsigned PARSER_SLICE_BYTES       = 128;

  // Offset width in bytes. 8 bits covers 0..255, which is more than enough
  // for a 128-byte header slice and provides headroom for overflow/error checks.
  localparam int unsigned PARSER_OFFSET_W          = 8;

  // Ingress port width is implementation-defined. 8 bits is a realistic
  // educational default for a moderate port-count switch pipeline.
  localparam int unsigned INGRESS_PORT_W           = 8;

  // Packet length width. 16 bits covers standard Ethernet frames and jumbo
  // frame lengths in a compact form.
  localparam int unsigned PKT_LEN_W                = 16;

  //--------------------------------------------------------------------------
  // Header lengths in bytes. These are used for offset computation and for
  // minimum-size checks in the parser pipeline.
  //--------------------------------------------------------------------------

  localparam int unsigned ETH_HDR_LEN_BYTES        = 14; // Ethernet II DA/SA/EtherType
  localparam int unsigned VLAN_HDR_LEN_BYTES       = 4;  // Single 802.1Q tag
  localparam int unsigned IPV4_MIN_HDR_LEN_BYTES   = 20; // IPv4 without options
  localparam int unsigned IPV6_BASE_HDR_LEN_BYTES  = 40; // IPv6 base header only
  localparam int unsigned UDP_HDR_LEN_BYTES        = 8;  // UDP fixed header
  localparam int unsigned TCP_MIN_HDR_LEN_BYTES    = 20; // TCP without options
  localparam int unsigned VXLAN_HDR_LEN_BYTES      = 8;  // Standard VXLAN header

  //--------------------------------------------------------------------------
  // Parser limits used to keep parsing bounded and deterministic.
  //--------------------------------------------------------------------------

  localparam int unsigned PARSER_MAX_VLAN_TAGS     = 1;  // Outer single VLAN only
  localparam int unsigned PARSER_SUPPORT_INNER_L2  = 1;  // Inner Ethernet allowed
  localparam int unsigned PARSER_SUPPORT_INNER_IP  = 1;  // Inner IPv4 allowed
  localparam int unsigned PARSER_SUPPORT_INNER_L4  = 1;  // Inner TCP/UDP allowed

  //--------------------------------------------------------------------------
  // Common EtherType constants.
  //--------------------------------------------------------------------------

  localparam logic [15:0] ETHERTYPE_IPV4           = 16'h0800; // Outer/inner IPv4
  localparam logic [15:0] ETHERTYPE_VLAN           = 16'h8100; // Single VLAN tag
  localparam logic [15:0] ETHERTYPE_IPV6           = 16'h86DD; // IPv6 base header

  //--------------------------------------------------------------------------
  // Common IP protocol / next-header values.
  //--------------------------------------------------------------------------

  localparam logic [7:0] IP_PROTO_TCP              = 8'd6;    // TCP
  localparam logic [7:0] IP_PROTO_UDP              = 8'd17;   // UDP

  //--------------------------------------------------------------------------
  // VXLAN constants.
  //--------------------------------------------------------------------------

  localparam logic [15:0] VXLAN_UDP_DST_PORT       = 16'd4789; // Standard VXLAN UDP port

  // VXLAN flags byte. In a simple bounded model, only the "I" bit is expected
  // to be set, indicating VNI validity. This constant is used by classification
  // and validation logic in later RTL.
  localparam logic [7:0] VXLAN_FLAGS_EXPECTED      = 8'h08;

  //----------------------------------------------------------------------------
  // Protocol classification enums
  //----------------------------------------------------------------------------

  // High-level parser stage classification. This is not a control FSM for the
  // full parser implementation; instead, it is a compact stage/status label that
  // can be carried for debug, trace, assertions, or stage-local classification.
  typedef enum logic [3:0] {
    PARSE_ST_IDLE        = 4'd0,  // No live packet in this context slot
    PARSE_ST_OUTER_L2    = 4'd1,  // Parsing outer Ethernet header
    PARSE_ST_OUTER_VLAN  = 4'd2,  // Parsing optional outer VLAN tag
    PARSE_ST_OUTER_L3    = 4'd3,  // Parsing outer IPv4/IPv6 header
    PARSE_ST_OUTER_L4    = 4'd4,  // Parsing outer TCP/UDP header
    PARSE_ST_VXLAN       = 4'd5,  // Parsing VXLAN header over outer UDP
    PARSE_ST_INNER_L2    = 4'd6,  // Parsing inner Ethernet header
    PARSE_ST_INNER_L3    = 4'd7,  // Parsing inner IPv4 header
    PARSE_ST_INNER_L4    = 4'd8,  // Parsing inner TCP/UDP header
    PARSE_ST_DONE        = 4'd9,  // Metadata fully formed
    PARSE_ST_ERROR       = 4'd10  // Parse encountered malformed/unsupported path
  } parser_stage_e;

  // L3 classification used for both outer and inner parse results.
  // Kept small because downstream logic usually needs only a compact protocol tag.
  typedef enum logic [1:0] {
    PARSER_L3_NONE       = 2'd0, // No valid L3 header identified
    PARSER_L3_IPV4       = 2'd1, // IPv4 header present
    PARSER_L3_IPV6       = 2'd2, // IPv6 header present
    PARSER_L3_OTHER      = 2'd3  // Unsupported/other L3 type observed
  } parser_l3_type_e;

  // L4 classification used for both outer and inner transport decode.
  typedef enum logic [1:0] {
    PARSER_L4_NONE       = 2'd0, // No valid L4 header identified
    PARSER_L4_TCP        = 2'd1, // TCP header present
    PARSER_L4_UDP        = 2'd2, // UDP header present
    PARSER_L4_OTHER      = 2'd3  // Unsupported/other L4 protocol observed
  } parser_l4_type_e;

  // Tunnel classification. Kept extensible even though only VXLAN is supported
  // in this bounded model.
  typedef enum logic [1:0] {
    PARSER_TUNNEL_NONE   = 2'd0, // No recognized tunnel
    PARSER_TUNNEL_VXLAN  = 2'd1, // VXLAN over UDP
    PARSER_TUNNEL_OTHER  = 2'd2  // Reserved for future tunnel types
  } parser_tunnel_type_e;

  // Parse disposition classification. Useful for downstream match-action stages
  // that may distinguish clean packets, malformed packets, and packets that are
  // syntactically valid but outside the supported parser profile.
  typedef enum logic [1:0] {
    PARSER_DISP_OK           = 2'd0, // Parse completed successfully
    PARSER_DISP_MALFORMED    = 2'd1, // Header malformed or too short
    PARSER_DISP_UNSUPPORTED  = 2'd2, // Valid packet, unsupported protocol stack
    PARSER_DISP_DROP         = 2'd3  // Parser recommends dropping packet
  } parser_disposition_e;

  //----------------------------------------------------------------------------
  // Parser context definition
  //
  // This record is intended to be carried stage-to-stage inside the parser
  // pipeline. It includes:
  //   - packet-level control
  //   - protocol validity bits
  //   - byte offsets to major header anchors
  //   - extracted fields needed for later stages
  //   - error/status bits
  //
  // It is intentionally richer than the final metadata output.
  //----------------------------------------------------------------------------

  typedef struct packed {
    //--------------------------------------------------------------------------
    // Packet-level control / lifetime tracking
    //--------------------------------------------------------------------------

    logic                      pipe_valid;     // Indicates this context slot contains a live packet
    logic                      sop;            // Marks start-of-packet for the current header slice
    logic                      eop;            // Marks end-of-packet if packet terminates in this beat
    logic                      rx_ok;          // Framing/FCS-admitted packet indicator from prior block
    logic                      hdr_trunc;      // Indicates required bytes are not fully present in 128B slice
    parser_stage_e             stage;          // Current parser stage classification for debug/control visibility
    parser_disposition_e       disposition;    // Aggregate parse result classification

    //--------------------------------------------------------------------------
    // Packet source information
    //--------------------------------------------------------------------------

    logic [INGRESS_PORT_W-1:0] ingress_port;   // Physical/logical ingress port for downstream policy and forwarding
    logic [PKT_LEN_W-1:0]      pkt_len;        // Full packet length as seen at ingress for policy and sanity checks

    //--------------------------------------------------------------------------
    // Byte offsets into the 128-byte parser slice
    //
    // These offsets anchor each parse layer. Storing them explicitly keeps the
    // microarchitecture feed-forward and avoids recomputing offsets repeatedly.
    //--------------------------------------------------------------------------

    logic [PARSER_OFFSET_W-1:0] outer_l2_offset;      // Byte offset to outer Ethernet header start
    logic [PARSER_OFFSET_W-1:0] outer_l3_offset;      // Byte offset to outer IP header start
    logic [PARSER_OFFSET_W-1:0] outer_l4_offset;      // Byte offset to outer TCP/UDP header start
    logic [PARSER_OFFSET_W-1:0] outer_payload_offset; // Byte offset to payload after outer L4
    logic [PARSER_OFFSET_W-1:0] vxlan_offset;         // Byte offset to VXLAN header start
    logic [PARSER_OFFSET_W-1:0] inner_l2_offset;      // Byte offset to inner Ethernet header start
    logic [PARSER_OFFSET_W-1:0] inner_l3_offset;      // Byte offset to inner IPv4 header start
    logic [PARSER_OFFSET_W-1:0] inner_l4_offset;      // Byte offset to inner TCP/UDP header start
    logic [PARSER_OFFSET_W-1:0] inner_payload_offset; // Byte offset to payload after inner L4

    //--------------------------------------------------------------------------
    // Protocol presence / classification bits
    //
    // These bits advance monotonically through the parser and give downstream
    // blocks a simple presence map without requiring them to infer protocol
    // layering from raw fields.
    //--------------------------------------------------------------------------

    logic                      outer_eth_valid; // Outer Ethernet header parsed successfully
    logic                      outer_vlan_valid;// Outer single VLAN tag present and parsed
    logic                      outer_ip_valid;  // Outer L3 header parsed successfully
    logic                      outer_l4_valid;  // Outer TCP/UDP header parsed successfully
    logic                      vxlan_valid;     // VXLAN header validated successfully
    logic                      inner_eth_valid; // Inner Ethernet header parsed successfully
    logic                      inner_ip_valid;  // Inner IPv4 header parsed successfully
    logic                      inner_l4_valid;  // Inner TCP/UDP header parsed successfully

    parser_l3_type_e           outer_l3_type;   // Outer L3 classification used by later stages
    parser_l4_type_e           outer_l4_type;   // Outer L4 classification used by later stages
    parser_tunnel_type_e       tunnel_type;     // Tunnel classification, currently none/VXLAN
    parser_l3_type_e           inner_l3_type;   // Inner L3 classification, bounded to IPv4/other
    parser_l4_type_e           inner_l4_type;   // Inner L4 classification, bounded to TCP/UDP/other

    //--------------------------------------------------------------------------
    // Outer Ethernet / VLAN fields
    //--------------------------------------------------------------------------

    logic [47:0]               outer_dst_mac;   // Outer destination MAC for L2 switching, ACL, and policy
    logic [47:0]               outer_src_mac;   // Outer source MAC for learning, ACL, and telemetry
    logic [15:0]               outer_ethertype; // Final outer EtherType after optional VLAN resolution
    logic [11:0]               outer_vlan_id;   // Outer VLAN ID for bridging, ACL, and tenant segmentation
    logic [2:0]                outer_vlan_pcp;  // VLAN PCP for QoS/class-of-service classification
    logic                      outer_vlan_dei;  // VLAN DEI for drop eligibility semantics

    //--------------------------------------------------------------------------
    // Outer IPv4 fields
    //--------------------------------------------------------------------------

    logic [31:0]               outer_ipv4_src;  // Outer IPv4 source address for routing, ACL, hashing
    logic [31:0]               outer_ipv4_dst;  // Outer IPv4 destination address for routing, ACL, hashing
    logic [7:0]                outer_ipv4_proto;// IPv4 protocol field used to classify TCP/UDP
    logic [7:0]                outer_ipv4_ttl;  // TTL used by routing, control-plane policing, telemetry
    logic [5:0]                outer_ipv4_dscp; // DSCP for QoS classification and policy
    logic [1:0]                outer_ipv4_ecn;  // ECN for congestion-aware processing
    logic [2:0]                outer_ipv4_flags;// Fragment/control bits for fragmentation handling
    logic [12:0]               outer_ipv4_frag_offset; // Fragment offset for detecting non-initial fragments

    //--------------------------------------------------------------------------
    // Outer IPv6 fields
    //--------------------------------------------------------------------------

    logic [127:0]              outer_ipv6_src;  // Outer IPv6 source address for routing and ACL
    logic [127:0]              outer_ipv6_dst;  // Outer IPv6 destination address for routing and ACL
    logic [7:0]                outer_ipv6_nh;   // IPv6 next-header field used to classify TCP/UDP
    logic [7:0]                outer_ipv6_hlim; // Hop limit used by L3 processing and telemetry
    logic [7:0]                outer_ipv6_tc;   // IPv6 traffic class for QoS/policy
    logic [19:0]               outer_ipv6_fl;   // IPv6 flow label for telemetry or hash seeding if desired

    //--------------------------------------------------------------------------
    // Outer L4 fields
    //--------------------------------------------------------------------------

    logic [15:0]               outer_l4_sport;  // Outer TCP/UDP source port for ACL, NAT-like policy, hashing
    logic [15:0]               outer_l4_dport;  // Outer TCP/UDP destination port for ACL, service recognition
    logic [8:0]                outer_tcp_flags; // Compact TCP flag vector for stateful policy / telemetry

    //--------------------------------------------------------------------------
    // VXLAN fields
    //--------------------------------------------------------------------------

    logic [23:0]               vxlan_vni;       // VXLAN VNI used for tenant/overlay lookup and tunnel termination

    //--------------------------------------------------------------------------
    // Inner Ethernet fields
    //--------------------------------------------------------------------------

    logic [47:0]               inner_dst_mac;   // Inner destination MAC for overlay bridge lookup
    logic [47:0]               inner_src_mac;   // Inner source MAC for learning and tenant policy
    logic [15:0]               inner_ethertype; // Inner EtherType, expected to resolve to IPv4 in this model

    //--------------------------------------------------------------------------
    // Inner IPv4 fields
    //--------------------------------------------------------------------------

    logic [31:0]               inner_ipv4_src;  // Inner IPv4 source for tenant routing, ACL, and flow hashing
    logic [31:0]               inner_ipv4_dst;  // Inner IPv4 destination for tenant routing, ACL, and flow hashing
    logic [7:0]                inner_ipv4_proto;// Inner IPv4 protocol field used to classify TCP/UDP
    logic [7:0]                inner_ipv4_ttl;  // Inner TTL for policy or telemetry if needed

    //--------------------------------------------------------------------------
    // Inner L4 fields
    //--------------------------------------------------------------------------

    logic [15:0]               inner_l4_sport;  // Inner TCP/UDP source port for overlay flow classification
    logic [15:0]               inner_l4_dport;  // Inner TCP/UDP destination port for overlay flow classification
    logic [8:0]                inner_tcp_flags; // Inner TCP flags for stateful policy if parser exports them

    //--------------------------------------------------------------------------
    // Error and exception bits
    //
    // These are intentionally fine-grained inside the context. The final output
    // metadata can either collapse them or forward them depending on system needs.
    //--------------------------------------------------------------------------

    logic                      err_too_short_outer_eth;   // Packet shorter than required for outer Ethernet decode
    logic                      err_too_short_vlan;        // Packet shorter than required for VLAN decode
    logic                      err_too_short_outer_ip;    // Packet shorter than required for outer IP decode
    logic                      err_too_short_outer_l4;    // Packet shorter than required for outer TCP/UDP decode
    logic                      err_too_short_vxlan;       // Packet shorter than required for VXLAN decode
    logic                      err_too_short_inner_eth;   // Packet shorter than required for inner Ethernet decode
    logic                      err_too_short_inner_ip;    // Packet shorter than required for inner IPv4 decode
    logic                      err_too_short_inner_l4;    // Packet shorter than required for inner TCP/UDP decode

    logic                      err_unsupported_outer_l3;  // Outer EtherType not supported by this bounded parser
    logic                      err_unsupported_outer_l4;  // Outer IP protocol not supported by this bounded parser
    logic                      err_outer_ipv4_options;    // Outer IPv4 options present if options are not supported
    logic                      err_outer_ipv4_frag;       // Outer IPv4 fragmented such that deep L4 parse is unsafe
    logic                      err_outer_ipv6_ext;        // Outer IPv6 extension header path not supported
    logic                      err_vxlan_flags;           // VXLAN flags do not match expected bounded model
    logic                      err_unsupported_inner_l3;  // Inner EtherType not supported by this bounded parser
    logic                      err_unsupported_inner_l4;  // Inner IPv4 protocol not supported by this bounded parser
    logic                      err_inner_ipv4_options;    // Inner IPv4 options present if options are not supported
    logic                      err_inner_ipv4_frag;       // Inner IPv4 fragmented such that deep L4 parse is unsafe

  } parser_context_t;

  //----------------------------------------------------------------------------
  // Parser metadata output definition
  //
  // This is the normalized contract exported to downstream match-action logic.
  // It is intentionally smaller and more consumer-oriented than parser_context_t.
  //----------------------------------------------------------------------------

  typedef struct packed {
    //--------------------------------------------------------------------------
    // Output validity / disposition
    //--------------------------------------------------------------------------

    logic                      valid;           // Metadata beat is valid and associated with a live packet
    logic                      parse_success;   // Parse completed successfully for supported protocol path
    logic                      parse_error;     // Packet hit malformed or truncation condition
    logic                      unsupported;     // Packet is well-formed enough to admit, but outside parser profile
    logic                      drop;            // Parser recommends drop or punt due to fatal parse outcome

    //--------------------------------------------------------------------------
    // Packet source attributes
    //--------------------------------------------------------------------------

    logic [INGRESS_PORT_W-1:0] ingress_port;    // Ingress port used by downstream forwarding and ACL logic
    logic [PKT_LEN_W-1:0]      pkt_len;         // Original packet length for policy, policing, or telemetry

    //--------------------------------------------------------------------------
    // Presence / classification bits
    //--------------------------------------------------------------------------

    logic                      outer_vlan_present; // Indicates outer VLAN metadata is valid
    logic                      outer_ipv4;         // Indicates outer IPv4 metadata is valid
    logic                      outer_ipv6;         // Indicates outer IPv6 metadata is valid
    logic                      outer_tcp;          // Indicates outer TCP metadata is valid
    logic                      outer_udp;          // Indicates outer UDP metadata is valid
    logic                      tunnel_vxlan;       // Indicates VXLAN tunnel was recognized
    logic                      inner_present;      // Indicates an inner packet was recognized and parsed
    logic                      inner_ipv4;         // Indicates inner IPv4 metadata is valid
    logic                      inner_tcp;          // Indicates inner TCP metadata is valid
    logic                      inner_udp;          // Indicates inner UDP metadata is valid

    //--------------------------------------------------------------------------
    // Outer L2 metadata
    //--------------------------------------------------------------------------

    logic [47:0]               outer_dst_mac;   // Outer destination MAC for bridging and ACL
    logic [47:0]               outer_src_mac;   // Outer source MAC for learning and ACL
    logic [11:0]               outer_vlan_id;   // Outer VLAN ID for segmentation and forwarding domain selection

    //--------------------------------------------------------------------------
    // Outer IP metadata
    //
    // Export both IPv4 and IPv6 banks explicitly. This keeps downstream logic
    // simple and avoids union typing, which can be awkward in some flows.
    //--------------------------------------------------------------------------

    logic [31:0]               outer_ipv4_src;  // Outer IPv4 source for routing, ACL, hash
    logic [31:0]               outer_ipv4_dst;  // Outer IPv4 destination for routing, ACL, hash
    logic [127:0]              outer_ipv6_src;  // Outer IPv6 source for routing, ACL, hash
    logic [127:0]              outer_ipv6_dst;  // Outer IPv6 destination for routing, ACL, hash
    logic [7:0]                outer_l3_proto;  // Outer IP protocol / next-header normalized into one field
    logic [7:0]                outer_ttl_hlim;  // Outer TTL or hop-limit normalized into one field
    logic [7:0]                outer_tc_qos;    // Outer DSCP/ECN or IPv6 traffic class normalized for QoS

    //--------------------------------------------------------------------------
    // Outer L4 metadata
    //--------------------------------------------------------------------------

    logic [15:0]               outer_l4_sport;  // Outer source port for ACL, service detection, ECMP hash
    logic [15:0]               outer_l4_dport;  // Outer destination port for ACL, service detection, ECMP hash
    logic [8:0]                outer_tcp_flags; // Outer TCP flags exported for stateful policy if needed

    //--------------------------------------------------------------------------
    // Tunnel metadata
    //--------------------------------------------------------------------------

    logic [23:0]               vxlan_vni;       // VXLAN VNI for overlay tenant identification and lookup

    //--------------------------------------------------------------------------
    // Inner metadata
    //--------------------------------------------------------------------------

    logic [47:0]               inner_dst_mac;   // Inner destination MAC for overlay bridge forwarding
    logic [47:0]               inner_src_mac;   // Inner source MAC for overlay learning/policy
    logic [31:0]               inner_ipv4_src;  // Inner IPv4 source for tenant routing and ACL
    logic [31:0]               inner_ipv4_dst;  // Inner IPv4 destination for tenant routing and ACL
    logic [7:0]                inner_l3_proto;  // Inner IPv4 protocol normalized for downstream use
    logic [15:0]               inner_l4_sport;  // Inner source port for tenant flow classification
    logic [15:0]               inner_l4_dport;  // Inner destination port for tenant flow classification
    logic [8:0]                inner_tcp_flags; // Inner TCP flags for tenant/stateful policy if required

    //--------------------------------------------------------------------------
    // Exported offsets
    //
    // These are optional in some products, but very useful in an educational
    // or instrumentation-friendly design because later blocks can directly index
    // into the stored header slice if additional fields are needed.
    //--------------------------------------------------------------------------

    logic [PARSER_OFFSET_W-1:0] outer_l3_offset;      // Byte offset of outer IP header
    logic [PARSER_OFFSET_W-1:0] outer_l4_offset;      // Byte offset of outer TCP/UDP header
    logic [PARSER_OFFSET_W-1:0] outer_payload_offset; // Byte offset after outer transport header
    logic [PARSER_OFFSET_W-1:0] inner_l2_offset;      // Byte offset of inner Ethernet header
    logic [PARSER_OFFSET_W-1:0] inner_l3_offset;      // Byte offset of inner IPv4 header
    logic [PARSER_OFFSET_W-1:0] inner_l4_offset;      // Byte offset of inner TCP/UDP header

    //--------------------------------------------------------------------------
    // Condensed status indicators
    //--------------------------------------------------------------------------

    logic                      hdr_trunc;       // Required parser bytes not fully present in first 128B
    logic                      outer_is_frag;   // Outer IPv4 fragmentation detected
    logic                      inner_is_frag;   // Inner IPv4 fragmentation detected
    logic                      malformed;       // Aggregated malformed-header indicator

  } parser_meta_t;

endpackage : ingress_parser_pkg
