# switch_learning

This directory is the default workspace for switch-oriented RTL work, including parser, lookup, metadata, and verification collateral.

## Recommended layout

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

## Directory intent

- `docs/specs/`
  Holds architecture and design specifications. Use this for parser microarchitecture docs, metadata contracts, stage breakdowns, and block-level requirements.

- `docs/notes/`
  Holds scratch notes, bring-up observations, timing notes, open questions, and design tradeoff writeups that are useful but not formal specs.

- `rtl/pkg/`
  Holds shared SystemVerilog packages. Put protocol constants, enums, packed structs, shared typedefs, and common parameter definitions here.

- `rtl/if/`
  Holds SystemVerilog interfaces and related modports. Use this for packet buses, parser-to-lookup metadata interfaces, and reusable verification-facing interface shells.

- `rtl/core/`
  Holds top-level switch-learning RTL blocks and major sub-blocks. This is the main location for modules such as ingress parser stages, metadata packers, lookup front-end logic, or pipeline control.

- `rtl/lib/`
  Holds smaller reusable helper blocks used by `rtl/core/`, such as extractors, skid buffers, mux helpers, counters, or alignment utilities.

- `tb/unit/`
  Holds focused unit-level testbenches for individual packages, interfaces, and modules.

- `tb/integration/`
  Holds subsystem-level testbenches that exercise multi-block flows, such as packet slice input through parser metadata output.

- `sim/`
  Holds simulation collateral such as filelists, waveform configs, do/tcl scripts, regression manifests, and directed packet stimulus files.

- `scripts/`
  Holds helper scripts for lint, sim invocation, waveform setup, documentation generation, or collateral packaging.

## Naming guidance

- Packages: `<block>_pkg.sv`
- Interfaces: `<bus_or_block>_if.sv`
- Top modules: `<block>_top.sv` or `<block>.sv`
- Unit testbenches: `tb_<block>.sv`
- Specs: `<topic>_spec.md`
- Notes: `<topic>_notes.md`

## Suggested parser-specific placement

For the ingress parser work we just outlined:

- parser package:
  `rtl/pkg/ingress_parser_pkg.sv`

- parser interfaces:
  `rtl/if/ingress_parser_if.sv`
  `rtl/if/parser_meta_if.sv`

- parser top and stages:
  `rtl/core/ingress_parser.sv`
  `rtl/core/ingress_parser_stage_l2.sv`
  `rtl/core/ingress_parser_stage_l3.sv`
  `rtl/core/ingress_parser_stage_l4.sv`
  `rtl/core/ingress_parser_meta_pack.sv`

- helper logic:
  `rtl/lib/header_extract.sv`
  `rtl/lib/offset_check.sv`

- specs and notes:
  `docs/specs/ingress_parser_spec.md`
  `docs/specs/parser_metadata_contract.md`
  `docs/notes/parser_timing_notes.md`

- verification:
  `tb/unit/tb_ingress_parser_pkg.sv`
  `tb/unit/tb_ingress_parser.sv`
  `tb/integration/tb_ingress_pipeline_parser.sv`

- simulation collateral:
  `sim/parser.f`
  `sim/run_parser.do`

## Practical rule of thumb

Keep shared contracts in `rtl/pkg/` and `rtl/if/`, keep synthesizable implementation in `rtl/core/` and `rtl/lib/`, and keep anything explanatory out of the RTL tree unless it directly affects compilation.
