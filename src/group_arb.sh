verilator --binary --trace rtl/switch_learning/rtl/core/rr_arb.sv rtl/switch_learning/rtl/core/group_arb.sv rtl/switch_learning/tb/unit/tb_group_arb.sv --top tb_group_arb
./obj_dir/Vtb_group_arb
gtkwave wave.vcd