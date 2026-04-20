`timescale 1ns/1ps
package systolic_array_pkg;

localparam int PROCESSING_ELEMENT_LATENCY = 1;
localparam int MAX_TILES = 16;
localparam int MAX_TILES_W = $clog2(MAX_TILES);


typedef struct packed{
    logic [MAX_TILES_W-1:0] num_tiles;
} instr_t;

endpackage