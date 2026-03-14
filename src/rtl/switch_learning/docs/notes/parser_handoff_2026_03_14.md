# Parser Handoff Notes

Date: 2026-03-14

## Purpose

This note captures the current state of the switch-learning ingress parser work so it can be resumed from another machine without relying on chat history.

## Workspace root

`C:\Users\Ezana\Documents\rtl_playground\src\rtl\switch_learning`

## What was defined

The current work is a production-style educational model of a bounded ingress packet parser for a modern data-center switch ASIC.

The parser target supports:

- Ethernet II
- single outer VLAN
- outer IPv4
- outer IPv6 base header only
- outer TCP
- outer UDP
- VXLAN over UDP
- inner Ethernet
- inner IPv4
- inner TCP/UDP

The parser assumptions and style:

- pipelined parser, not a single iterative FSM
- 1024-bit input bus carrying first 128 bytes of header data
- bounded deterministic parsing depth
- explicit byte offset tracking across parse layers
- outer and inner headers treated as separate anchored parse domains
- parser valid bits and error bits move stage to stage

## Microarchitecture summary

The parser architecture previously defined was:

1. Stage 0: outer Ethernet detect
2. Stage 1: VLAN resolution and outer L3 offset compute
3. Stage 2: outer IPv4/IPv6 parse and outer L4 offset compute
4. Stage 3: outer TCP/UDP parse and VXLAN candidate detection
5. Stage 4: VXLAN validation and inner L2 anchor formation
6. Stage 5: inner Ethernet + inner IPv4 + inner TCP/UDP parse
7. Stage 6: metadata pack and final error/status consolidation

Important architectural rule:

- keep header data stationary as a 128-byte slice
- move parser context, offsets, valid bits, and extracted fields through pipeline registers

## Files already created

### Documentation / workspace structure

- `README.md`

### RTL package and module shell

- `rtl/pkg/ingress_parser_pkg.sv`
- `rtl/core/ingress_parser.sv`

## File intent

### `rtl/pkg/ingress_parser_pkg.sv`

Contains:

- parser constants and protocol constants
- enums for parser stage and protocol classification
- packed parser context struct
- packed normalized parser metadata struct

This file is intended to be the shared contract between parser stages and downstream match-action logic.

### `rtl/core/ingress_parser.sv`

Contains:

- top-level parser module declaration only
- no parsing logic yet
- ports include clock/reset, packet slice input, keep mask, ingress port, packet length, metadata output, and parse error output

## Directory scheme created

```text
switch_learning/
├── README.md
├── docs/
│   ├── specs/
│   └── notes/
├── rtl/
│   ├── pkg/
│   ├── if/
│   ├── core/
│   └── lib/
├── tb/
│   ├── unit/
│   └── integration/
├── sim/
└── scripts/
```

Recommended parser file placement:

- specs: `docs/specs/`
- notes/handoffs: `docs/notes/`
- packages: `rtl/pkg/`
- interfaces: `rtl/if/`
- parser blocks: `rtl/core/`
- helper blocks: `rtl/lib/`
- parser testbenches: `tb/unit/` and `tb/integration/`

## Recommended next steps

The most sensible next steps, in order, are:

1. Add the formal parser microarchitecture spec document into `docs/specs/`
2. Add a parser interface file in `rtl/if/` for cleaner boundary definition
3. Split the future implementation into stage-local modules or at least stage-local register groups
4. Define reset defaults for `parser_context_t` and `parser_meta_t`
5. Decide whether `parse_error_o` is enough or whether a separate `drop_o` is needed
6. Build unit testbench scaffolding before implementing the parser datapath

## Good candidate next files

- `docs/specs/ingress_parser_spec.md`
- `rtl/if/ingress_parser_if.sv`
- `rtl/core/ingress_parser_stage_l2.sv`
- `rtl/core/ingress_parser_stage_l3.sv`
- `rtl/core/ingress_parser_stage_l4.sv`
- `rtl/core/ingress_parser_meta_pack.sv`
- `tb/unit/tb_ingress_parser_pkg.sv`
- `tb/unit/tb_ingress_parser.sv`

## Notes for resume

When resuming on another machine:

- open the workspace at `switch_learning`
- start from `README.md`
- review `rtl/pkg/ingress_parser_pkg.sv`
- review `rtl/core/ingress_parser.sv`
- use this handoff note to reconstruct the design context

## Suggested resume prompt

If starting a new session, a good resume prompt is:

`Continue the switch_learning ingress parser work. Use docs/notes/parser_handoff_2026_03_14.md and the files under rtl/pkg and rtl/core as the source of truth. Next, add the formal parser spec under docs/specs and then define a parser interface in rtl/if, but do not implement parser logic yet.`
