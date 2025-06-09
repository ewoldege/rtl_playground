verilator --binary --trace rtl/lpf.sv tb/tb_lpf.sv --top tb_lpf
./obj_dir/Vtb_lpf
gtkwave wave.vcd