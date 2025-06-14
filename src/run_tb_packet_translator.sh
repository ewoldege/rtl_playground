verilator --binary --trace --Wno-WIDTHEXPAND --Wno-WIDTHTRUNC rtl/async_fifo.sv rtl/packet_translator.sv tb/tb_packet_translator.sv --top tb_packet_translator
./obj_dir/Vtb_packet_translator
gtkwave wave.vcd