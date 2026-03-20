verilator --binary --trace --Wno-lint rtl/gearbox_v2.sv tb/tb_gearbox_v2.sv --top tb_gearbox_v2
./obj_dir/Vtb_gearbox_v2
gtkwave wave.vcd