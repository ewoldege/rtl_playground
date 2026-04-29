#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

verilator --binary --trace --timing -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND \
    rtl/fifo_fwft_sync.sv \
    tb/tb_fifo_fwft_sync.sv \
    --top tb_fifo_fwft_sync

./obj_dir/Vtb_fifo_fwft_sync

echo "VCD written to $(pwd)/wave_fifo_fwft_sync.vcd"
