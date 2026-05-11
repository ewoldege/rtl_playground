# Ingress Parser Microarchitecture Specification

## 1. Top-down role in the switch pipeline

The ingress parser sits between packet reception and the match-action / lookup pipeline.

At a high level:

```text
[RX MAC / framing / FCS check]
              |
              v
   [header slice / packet buffer]
              |
              v
        [ingress parser]
              |
              v
   [lookup / ACL / forwarding / tunnel]
              |
              v
   [rewrite / queue / traffic manager]
```

The parser converts a raw packet header byte stream into fixed, normalized metadata that downstream blocks can consume without re-decoding protocol structure.

Its role is to:

- identify which protocol headers are present
- compute offsets to important headers and payload boundaries
- extract forwarding, policy, and tunnel keys
- flag malformed or unsupported packets
- emit a compact metadata record for downstream stages

This parser is intentionally modeled as a bounded, fixed-function ASIC parser, not as a recursive software decoder.

## 2. Supported protocol profile

Supported outer protocol stack:

- Ethernet II
- optional single VLAN tag
- IPv4
- IPv6 base header only
- TCP
- UDP
- VXLAN over UDP

Supported inner protocol stack after VXLAN:

- inner Ethernet
- inner IPv4
- inner TCP or UDP

The parser input is a `1024-bit` bus carrying the first `128 bytes` of header data.

## 3. Design philosophy

This parser is a feed-forward pipelined parser.

Each stage:

- receives the stable 128-byte header slice
- receives a parser context register from the prior stage
- extracts only the fields needed by that stage
- computes the next offset anchor
- updates protocol valid bits and error bits
- forwards the updated context to the next stage

The header bytes are treated as stationary. The main object moving through the pipeline is the parser context.

This is a realistic abstraction of how a modern switch ASIC parser is structured.

## 4. Major architectural blocks

```text
                         Ingress Parser

hdr[1023:0] -----------------------------------------------+
                                                           |
valid/sop/eop --------------------------------------------+|
sideband ------------------------------------------------+||
                                                         vvv
    +-----------------------------------------------------------+
    | Header Slice Register / Stable Byte Addressable View      |
    +----------------------------+------------------------------+
                                 |
                                 v
    +-----------------------------------------------------------+
    | Stage 0: Outer Ethernet Parse                            |
    +----------------------------+------------------------------+
                                 |
                                 v
    +-----------------------------------------------------------+
    | Stage 1: VLAN Resolve + Outer L3 Offset Compute          |
    +----------------------------+------------------------------+
                                 |
                                 v
    +-----------------------------------------------------------+
    | Stage 2: Outer IPv4 / IPv6 Parse                         |
    +----------------------------+------------------------------+
                                 |
                                 v
    +-----------------------------------------------------------+
    | Stage 3: Outer TCP / UDP Parse                           |
    +----------------------------+------------------------------+
                                 |
                                 v
    +-----------------------------------------------------------+
    | Stage 4: VXLAN Detect + Inner Anchor                     |
    +----------------------------+------------------------------+
                                 |
                                 v
    +-----------------------------------------------------------+
    | Stage 5: Inner Ethernet / IPv4 / TCP-UDP Parse           |
    +----------------------------+------------------------------+
                                 |
                                 v
    +-----------------------------------------------------------+
    | Stage 6: Metadata Pack / Status / Error Consolidation    |
    +----------------------------+------------------------------+
                                 |
                                 v
                       metadata_to_lookup[]
```

Main architectural elements:

- header slice register or buffer
- byte-addressed field extract network
- parser context register between stages
- bounded deterministic parse graph

## 5. Offset tracking model

Offset tracking is central to the design.

The parser uses explicit byte offsets to anchor each parse layer:

- `outer_l2_offset`
- `outer_l3_offset`
- `outer_l4_offset`
- `outer_payload_offset`
- `vxlan_offset`
- `inner_l2_offset`
- `inner_l3_offset`
- `inner_l4_offset`
- `inner_payload_offset`

The offsets are computed from known prior anchors:

- outer Ethernet starts at byte `0`
- outer L3 starts at byte `14` or `18` depending on VLAN
- outer L4 starts at `outer_l3_offset + ipv4_ihl*4` or `outer_l3_offset + 40`
- outer payload starts after outer TCP or UDP
- VXLAN starts at `outer_payload_offset`
- inner Ethernet starts at `vxlan_offset + 8`
- inner IPv4 starts at `inner_l2_offset + 14`
- inner L4 starts at `inner_l3_offset + inner_ipv4_ihl*4`

This explicit offset model keeps the datapath deterministic and hardware-friendly.

## 6. Outer versus inner header handling

Outer and inner parsing are handled as two separate anchored parse domains.

Outer parsing:

- establishes the transport and tunnel context
- identifies whether the outer packet is plain L2/L3/L4 traffic or VXLAN tunneled traffic

Inner parsing:

- is only enabled if VXLAN is recognized and validated
- starts from `inner_l2_offset`
- extracts tenant-visible L2/L3/L4 fields

This separation is important because downstream policy may use:

- outer fields for tunnel termination, underlay forwarding, ACL, and ECMP
- inner fields for tenant routing, overlay forwarding, and tenant ACL

## 7. Stage-by-stage pipeline breakdown

### Stage 0: packet admit and outer Ethernet parse

Purpose:

- initialize parser context
- parse outer Ethernet DA/SA/EtherType candidate

Main work:

- set `outer_l2_offset = 0`
- extract outer destination MAC
- extract outer source MAC
- extract EtherType at bytes `12:13`
- establish minimum length validity for outer Ethernet

Outputs:

- outer Ethernet fields
- initial EtherType candidate
- `outer_eth_valid`

### Stage 1: VLAN resolution and outer L3 offset compute

Purpose:

- resolve optional single VLAN tag
- determine final outer EtherType and outer L3 offset

Main work:

- if EtherType is `0x8100`, parse VLAN TCI and encapsulated EtherType
- set `outer_l3_offset = 18` when VLAN present
- otherwise set `outer_l3_offset = 14`
- classify outer L3 as IPv4, IPv6, or unsupported

Outputs:

- VLAN fields
- final outer EtherType
- outer L3 type
- `outer_l3_offset`

### Stage 2: outer IPv4 / IPv6 parse

Purpose:

- parse outer IP header
- determine outer L4 type and outer L4 offset

Outer IPv4 work:

- extract version and IHL
- extract DSCP/ECN
- extract protocol
- extract TTL
- extract source and destination IPv4
- extract flags and fragment offset
- compute `outer_l4_offset = outer_l3_offset + ihl*4`

Outer IPv6 work:

- extract version / traffic class / flow label
- extract next-header
- extract hop limit
- extract source and destination IPv6
- compute `outer_l4_offset = outer_l3_offset + 40`

Outputs:

- outer IP fields
- `outer_l4_offset`
- outer L4 protocol classification
- fragmentation and unsupported-extension indications

### Stage 3: outer TCP / UDP parse

Purpose:

- parse outer TCP or UDP
- establish outer payload offset
- detect VXLAN candidacy

Outer UDP work:

- extract source port
- extract destination port
- extract UDP length
- set `outer_payload_offset = outer_l4_offset + 8`
- detect VXLAN if destination port is `4789`

Outer TCP work:

- extract source port
- extract destination port
- extract data offset
- extract TCP flags
- set `outer_payload_offset = outer_l4_offset + data_offset*4`

Outputs:

- outer L4 ports
- outer TCP flags if applicable
- `outer_payload_offset`
- VXLAN candidate bit

### Stage 4: VXLAN detect and inner anchor formation

Purpose:

- validate VXLAN over outer UDP
- establish inner Ethernet anchor

Main work:

- parse VXLAN header at `outer_payload_offset`
- validate expected VXLAN flags
- extract `vxlan_vni`
- set `inner_l2_offset = outer_payload_offset + 8`

Outputs:

- `vxlan_valid`
- `vxlan_vni`
- `inner_l2_offset`

### Stage 5: inner Ethernet / inner IPv4 / inner TCP-UDP parse

Purpose:

- parse the bounded inner stack after VXLAN

Inner Ethernet work:

- extract inner DA/SA/EtherType
- compute `inner_l3_offset = inner_l2_offset + 14`

Inner IPv4 work:

- extract version/IHL
- extract protocol
- extract source and destination IPv4
- compute `inner_l4_offset = inner_l3_offset + ihl*4`

Inner L4 work:

- if TCP, extract ports, flags, and data offset
- if UDP, extract ports and length
- compute `inner_payload_offset`

Outputs:

- inner Ethernet fields
- inner IPv4 fields
- inner TCP/UDP fields

### Stage 6: metadata pack and finalization

Purpose:

- convert parser context into fixed metadata output
- consolidate errors and final status

Outputs:

- normalized parser metadata
- parse success / error / unsupported indication
- drop-eligible or error output as defined by the block interface

## 8. Pipeline-valid and header-valid movement

The packet-level pipeline valid bit moves stage to stage independently from per-header valid bits.

```text
valid_in ---> v0 ---> v1 ---> v2 ---> v3 ---> v4 ---> v5 ---> v6
```

Per-header valid bits are accumulated monotonically:

```text
Stage   outer_eth  vlan  outer_ip  outer_l4  vxlan  inner_eth  inner_ip  inner_l4
-----   ---------  ----  --------  --------  -----  ---------  --------  --------
S0         1         0      0         0        0        0         0         0
S1         1       0/1      0         0        0        0         0         0
S2         1       0/1      1         0        0        0         0         0
S3         1       0/1      1         1        0        0         0         0
S4         1       0/1      1         1       0/1       0         0         0
S5         1       0/1      1         1       0/1      0/1       0/1       0/1
S6         final metadata emitted
```

Once a parse error is set, it should remain set. Later stages may still pass context forward for final metadata generation, but should not attempt unsupported deeper parsing.

## 9. Parser context definition intent

The internal parser context should carry:

- packet-level control state
- ingress sideband attributes
- parse offsets
- protocol presence bits
- protocol classification enums
- extracted header fields
- fine-grained error flags

This context is richer than the final metadata output because it is intended for stage-to-stage transport inside the parser pipeline.

## 10. Metadata output definition intent

The final metadata exported downstream should include:

- packet disposition: success, error, unsupported, drop
- outer L2 fields: MACs and VLAN ID
- outer L3 fields: IPv4 or IPv6 source/destination, normalized protocol, TTL/hop-limit, traffic class
- outer L4 fields: ports and TCP flags
- tunnel field: VXLAN VNI
- inner L2/L3/L4 fields for overlay-aware lookup
- header offsets if later stages need direct access into the stored header slice
- condensed malformed/truncation/fragment indicators

The metadata should be shaped to feed match-action and lookup stages directly.

## 11. Assumptions and simplifications

This model intentionally uses a realistic but bounded protocol envelope.

Supported:

- Ethernet II
- single VLAN tag
- outer IPv4 or IPv6 base header
- outer TCP or UDP
- VXLAN over UDP
- inner Ethernet
- inner IPv4
- inner TCP or UDP

Not supported in this model:

- QinQ
- MPLS
- ARP
- ICMP deep parse
- IPv6 extension header walk
- GRE
- GENEVE
- NVGRE
- inner IPv6
- inner VLAN
- full TCP option parse
- checksum verification in parser datapath
- iterative fetch beyond first 128B
- programmable parser graph

Recommended IPv4 simplifications:

- require outer IPv4 IHL = 5 unless expanded later
- require inner IPv4 IHL = 5 unless expanded later
- flag fragmentation and stop deeper reliable L4 parse when needed

## 12. Timing and critical path concerns

Main timing risks:

- dynamic byte extraction at computed offsets
- offset computation followed by immediate data extraction
- protocol compare trees in the same stage
- wide fanout of valid, type, and error signals

Important implementation strategies:

- keep the 128-byte header data stationary
- pipeline the parser context and computed offsets
- limit each stage to one major variable-offset extraction domain
- register computed offsets before using them in the next level of parse
- keep error handling monotonic

Most timing-sensitive stage:

- outer or inner IPv4 parse tends to be the hardest stage because it combines header extraction, protocol classification, and variable L4 offset computation

If frequency is aggressive, the outer L3 and inner L3 work may need further subdivision beyond the conceptual stages listed here.

## 13. Mapping to a real modern switch ASIC parser

This model is believable because it matches key properties of real switch ASIC ingress parsers:

- bounded parse depth
- fixed-function protocol profile
- header slice based operation
- context-driven pipelining
- explicit outer versus inner metadata
- deterministic latency

Where real products may differ:

- more protocols and exception paths
- semi-programmable parser graphs
- tighter coupling to hash extraction and policy engines
- richer malformed / punt / trap handling

## 14. Condensed architecture summary

```text
1. Capture first 128B header slice
2. Parse outer Ethernet
3. Resolve optional VLAN and compute outer L3 anchor
4. Parse outer IP and compute outer L4 anchor
5. Parse outer TCP/UDP and detect VXLAN
6. If VXLAN, compute inner Ethernet anchor
7. Parse inner Ethernet, inner IPv4, and inner TCP/UDP
8. Emit normalized metadata and parser status
```

Key design rule:

```text
Each stage consumes a stable header slice and a registered parser context,
extracts only the fields relevant to that stage, computes the next offset,
and advances valid and error state forward in a deterministic pipeline.
```
