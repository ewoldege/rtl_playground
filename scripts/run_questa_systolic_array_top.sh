#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK_LIB="${REPO_ROOT}/.questa_work_systolic_array_top"
DO_FILE="${SCRIPT_DIR}/questa_systolic_array_top.do"

QUESTA_BIN_DEFAULT="${HOME}/altera/25.1std/questa_fse/bin"
QUESTA_BIN="${QUESTA_BIN:-$QUESTA_BIN_DEFAULT}"

usage() {
  cat <<'EOF'
Usage: run_questa_systolic_array_top.sh [--batch] [--clean]

  --batch  Run the testbench to completion in the terminal and exit.
  --clean  Remove and recreate the local Questa work library before compile.

Environment:
  QUESTA_BIN  Directory containing vsim/vlog/vlib.
EOF
}

BATCH=0
CLEAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --batch)
      BATCH=1
      ;;
    --clean)
      CLEAN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ ! -x "${QUESTA_BIN}/vsim" || ! -x "${QUESTA_BIN}/vlog" || ! -x "${QUESTA_BIN}/vlib" ]]; then
  echo "Could not find Questa executables in ${QUESTA_BIN}" >&2
  echo "Set QUESTA_BIN to the directory that contains vsim/vlog/vlib." >&2
  exit 1
fi

export PATH="${QUESTA_BIN}:${PATH}"

if [[ ${CLEAN} -eq 1 ]]; then
  rm -rf "${WORK_LIB}"
fi

if [[ ! -d "${WORK_LIB}" ]]; then
  vlib "${WORK_LIB}"
fi

cd "${REPO_ROOT}"

vlog -sv -work "${WORK_LIB}" \
  src/rtl/systolic_array/systolic_array_pkg.sv \
  src/rtl/sram_cell.sv \
  src/rtl/systolic_array/processing_element.sv \
  src/rtl/systolic_array/systolic_array_cell.sv \
  src/rtl/systolic_array/banked_accum.sv \
  src/rtl/systolic_array/systolic_array_top.sv \
  src/tb/tb_systolic_array_top.sv

if [[ ${BATCH} -eq 1 ]]; then
  vsim -c -work "${WORK_LIB}" tb_systolic_array_top -do "run -all; quit -f"
else
  vsim -work "${WORK_LIB}" -do "${DO_FILE}" tb_systolic_array_top
fi
