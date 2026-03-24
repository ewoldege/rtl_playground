`timescale 1ns/1ps

module simple_cam 
#(
    parameter CAM_W = 32,
    parameter CAM_DEPTH = 64,
    parameter CAM_DEPTH_W = $clog2(CAM_DEPTH)
)
(
    input clk,
    input rst_n,

    input logic wren,
    input logic [CAM_W-1:0] wdata,
    input logic [CAM_DEPTH_W-1:0] waddr,

    input  logic lookup_en,
    input  logic [CAM_W-1:0] lookup_val,
    output logic [CAM_DEPTH_W-1:0] lookup_winner,
    output logic lookup_resp_valid,
    output logic lookup_hit
);

logic [CAM_DEPTH-1:0][CAM_W-1:0] cam;
logic [CAM_DEPTH-1:0] cam_addr_valid;
logic [CAM_DEPTH-1:0] compare_result;
logic [CAM_DEPTH_W-1:0] cam_lookup_winner;
logic [CAM_W-1:0] lookup_val_gated;

assign lookup_val_gated = lookup_en ? lookup_val : '0;

// Write Procedure
always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        cam_addr_valid <= '0;
    end else begin
        if(wren) begin
            cam[waddr] <= wdata;
            cam_addr_valid[waddr] <= 1'b1;
        end
    end
end

// Read Procedure
always_comb begin
    // Per row comparator each cycle
    for(int i = 0; i < CAM_DEPTH; i++) begin
        compare_result[i] = lookup_en && cam_addr_valid[i] && (cam[i] == lookup_val_gated);
    end

    // Priority encoder - lowest address wins
    cam_lookup_winner = '0;
    for(int i = CAM_DEPTH-1; i >= 0; i--) begin
        if(compare_result[i]) begin
            cam_lookup_winner = i[CAM_DEPTH_W-1:0];
        end
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        lookup_resp_valid <= 1'b0;
    end else begin
        lookup_resp_valid <= lookup_en;
        if(lookup_en) begin
            lookup_winner <= cam_lookup_winner;
            lookup_hit <= |compare_result;
        end
    end
end
endmodule