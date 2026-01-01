create_clock -period 2.500 -name clk -waveform {0.000 1.250} [get_ports -filter { NAME =~  "*clk*" && DIRECTION == "IN" }]
