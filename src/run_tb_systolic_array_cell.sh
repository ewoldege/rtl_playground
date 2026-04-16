#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

verilator --binary --trace --timing \
    rtl/systolic_array/systolic_array_pkg.sv \
    rtl/systolic_array/processing_element.sv \
    rtl/systolic_array/systolic_array_cell.sv \
    tb/tb_systolic_array_cell.sv \
    --top tb_systolic_array_cell

./obj_dir/Vtb_systolic_array_cell

echo "VCD written to $(pwd)/wave_systolic_array_cell.vcd"
