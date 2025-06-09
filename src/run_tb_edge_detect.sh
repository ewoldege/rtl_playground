verilator --binary --trace rtl/edge_detect.sv tb/tb_edge_detect.sv --top tb_edge_detect
./obj_dir/Vtb_edge_detect
gtkwave wave.vcd