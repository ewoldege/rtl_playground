verilator --binary --trace --Wno-WIDTHEXPAND --Wno-WIDTHTRUNC --Wno-TIMESCALEMOD --Wno-UNOPTFLAT rtl/data_sampler.sv tb/tb_data_sampler.sv --top tb_data_sampler
./obj_dir/Vtb_data_sampler
gtkwave wave.vcd