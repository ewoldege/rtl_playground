#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

verilator --binary --trace-fst --timing -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND \
    rtl/systolic_array/systolic_array_pkg.sv \
    rtl/sram_cell.sv \
    rtl/fifo_fwft_sync.sv \
    rtl/systolic_array/processing_element.sv \
    rtl/systolic_array/systolic_array_cell.sv \
    rtl/systolic_array/banked_accum.sv \
    rtl/systolic_array/systolic_array_top.sv \
    tb/tb_systolic_array_top.sv \
    --top tb_systolic_array_top

./obj_dir/Vtb_systolic_array_top "$@"

echo "FST written to $(pwd)/wave_systolic_array_top.fst"
