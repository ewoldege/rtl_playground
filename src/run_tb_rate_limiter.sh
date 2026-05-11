verilator --binary --trace --Wno-WIDTHTRUNC --Wno-WIDTHEXPAND --Wno-INITIALDLY rtl/rate_limiter.sv tb/tb_rate_limiter.sv --top tb_rate_limiter
./obj_dir/Vtb_rate_limiter
gtkwave wave.vcd
