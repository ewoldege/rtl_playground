verilator --binary --trace rtl/fixed_point_arithmetic.sv tb/tb_fixed_point_arithmetic.sv --top tb_fixed_point_arithmetic
./obj_dir/Vtb_fixed_point_arithmetic
gtkwave wave.vcd