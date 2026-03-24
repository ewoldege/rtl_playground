verilator --binary --trace --Wno-WIDTHEXPAND --Wno-WIDTHTRUNC --Wno-TIMESCALEMOD --Wno-UNOPTFLAT --Wno-INITIALDLY rtl/async_fifo_v2.sv tb/tb_async_fifo_v2.sv --top tb_async_fifo_v2
./obj_dir/Vtb_async_fifo_v2
gtkwave wave.vcd