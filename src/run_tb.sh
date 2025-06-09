verilator --binary --trace rtl/adder.sv tb/tb.sv --top tb
./obj_dir/Vtb
gtkwave wave.vcd