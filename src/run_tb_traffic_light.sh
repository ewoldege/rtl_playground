verilator --binary --trace rtl/traffic_light.sv tb/tb_traffic_light.sv --top tb_traffic_light
./obj_dir/Vtb_traffic_light
gtkwave wave.vcd