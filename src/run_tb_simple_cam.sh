verilator --binary --trace -Wno-WIDTHTRUNC -Wno-INITIALDLY rtl/simple_cam.sv tb/tb_simple_cam.sv --top tb_simple_cam
./obj_dir/Vtb_simple_cam
gtkwave wave.vcd