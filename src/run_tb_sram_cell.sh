verilator --binary --trace -Wno-WIDTHTRUNC -Wno-INITIALDLY rtl/sram_cell.sv tb/tb_sram_cell.sv --top tb_sram_cell
./obj_dir/Vtb_sram_cell
