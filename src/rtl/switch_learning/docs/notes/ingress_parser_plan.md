# Ingress Parser Planning Notes

Date: 2026-03-14

## Scope

These notes capture the implementation planning guidance that accompanied the parser microarchitecture definition.

They are intentionally more action-oriented than the formal spec.

## Current source-of-truth files

- `docs/specs/ingress_parser_spec.md`
- `rtl/pkg/ingress_parser_pkg.sv`
- `rtl/core/ingress_parser.sv`

## Design intent

The current intent is to build the parser in a disciplined progression:

1. specification first
2. package and interface contract second
3. module shells and stage boundaries third
4. parser datapath and extraction logic after the contracts are stable
5. unit verification scaffolding before full functional completion

## Recommended file plan

Suggested next files:

- `rtl/if/ingress_parser_if.sv`
- `rtl/core/ingress_parser_stage_l2.sv`
- `rtl/core/ingress_parser_stage_vlan_l3_anchor.sv`
- `rtl/core/ingress_parser_stage_outer_l3.sv`
- `rtl/core/ingress_parser_stage_outer_l4.sv`
- `rtl/core/ingress_parser_stage_vxlan.sv`
- `rtl/core/ingress_parser_stage_inner.sv`
- `rtl/core/ingress_parser_meta_pack.sv`
- `rtl/lib/header_extract.sv`
- `rtl/lib/offset_check.sv`
- `tb/unit/tb_ingress_parser_pkg.sv`
- `tb/unit/tb_ingress_parser.sv`

## Practical implementation guidance

### 1. Keep the first RTL milestone narrow

The first implementation milestone should not try to solve the entire tunnel stack at once.

A sensible progression is:

- milestone 1: outer Ethernet + VLAN + outer IPv4 + outer UDP/TCP metadata
- milestone 2: outer VXLAN detect and VNI extraction
- milestone 3: inner Ethernet + inner IPv4 + inner TCP/UDP

This reduces bring-up complexity and keeps debug localized.

### 2. Preserve the contract boundary

Keep the package file stable once downstream metadata consumers start depending on it.

This means:

- avoid churn in field names
- avoid repacking enums unless necessary
- add new fields carefully and document them

### 3. Decide early whether to use interfaces

The current top-level shell uses plain ports, which is fine.

If the parser grows into several submodules, adding SystemVerilog interfaces under `rtl/if/` is recommended for:

- parser slice input bundle
- parser metadata output bundle
- internal stage-to-stage context transport if the team prefers that style

### 4. Treat offsets as first-class design objects

Do not hide offset arithmetic throughout the RTL.

Prefer:

- named offset signals
- explicit comments for each anchor
- dedicated helpers for byte-coverage checks

This will make the parser easier to review and debug.

### 5. Keep error handling monotonic

Recommended rule:

- once malformed or unsupported is set, do not clear it later
- permit metadata completion for debug and observability
- suppress unsupported deeper parse actions once the path is invalid

### 6. Be careful with timing in the L3 stages

The likely hardest logic cones are:

- IPv4 IHL decode plus outer L4 offset compute
- inner IPv4 IHL decode plus inner L4 offset compute
- dynamic field extraction from computed byte offsets

If needed, split stage work further before the design shape becomes entrenched.

## Verification planning notes

Unit verification should focus on deterministic header profiles first.

Suggested early tests:

- Ethernet II + IPv4 + UDP
- Ethernet II + VLAN + IPv4 + TCP
- Ethernet II + IPv6 + UDP
- Ethernet II + VLAN + IPv4 + UDP + VXLAN + inner Ethernet + inner IPv4 + TCP
- unsupported EtherType
- fragmented IPv4
- outer IPv6 with unsupported extension-header path indication
- too-short packet cases using `keep_i`

Useful testbench checks:

- offsets match expected byte positions
- valid bits assert only when the corresponding header is really present
- unsupported and malformed are distinguished correctly
- VNI is extracted only when VXLAN is actually valid

## Open decisions

These decisions were not finalized yet:

- whether to export `drop_o` separately from `parse_error_o`
- whether to support IPv4 options in outer or inner headers
- whether to keep the parser as one module with stage-local registers or split into per-stage submodules
- whether to export all offsets in final metadata or keep some internal

## Recommended next step

The next most useful step after these docs is:

- add `rtl/if/ingress_parser_if.sv`

That gives the design a cleaner boundary before internal RTL is implemented.
