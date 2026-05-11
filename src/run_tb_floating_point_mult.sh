#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

verilator --binary --trace --timing -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND \
    rtl/systolic_array/floating_point_pkg.sv \
    rtl/systolic_array/floating_point_mult.sv \
    tb/tb_floating_point_mult.sv \
    --top tb_floating_point_mult

./obj_dir/Vtb_floating_point_mult "$@"

echo "VCD written to $(pwd)/wave_floating_point_mult.vcd"
