verilator --binary --trace --Wno-lint rtl/gearbox.sv tb/tb_gearbox.sv --top tb_gearbox
./obj_dir/Vtb_gearbox
gtkwave wave.vcd