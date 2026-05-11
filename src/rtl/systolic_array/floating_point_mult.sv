import floating_point_pkg::*;

module floating_point_mult
#(

)
(
    input clk,
    input rst_n,

    input fl_6 a_in,
    input fl_6 b_in,
    input logic valid_in,

    output fl_6 c_out,
    output logic overflow,
    output logic valid_out
);

localparam int MAX_FL_MULT_DLY = 3;
localparam int REG_STAGE = 0;
localparam int COMP_STAGE = 1;
localparam int ALIGN_STAGE = 2;

logic [MAX_FL_MULT_DLY-1:0] valid_pipeline_reg;
fl_6 a_reg;
fl_6 b_reg;
logic [8:0] c_exp_raw;
logic [15:0] c_mantissa_raw;
logic c_sign_raw;

logic [8:0] c_exp_algn;
logic [15:0] c_mantissa_algn;
logic c_sign_algn;

logic [7:0] mantissa_round;

logic zero_check;
logic zero_check_reg;
logic zero_check_reg2;

function automatic logic [7:0] round_to_nearest_even(
    input logic [14:0] raw
);
    logic round_up;
    logic [8:0] result_temp;
    logic [7:0] result;
    logic sticky;
    logic gaurd;
    logic lsb;
    logic [7:0] kept;

    sticky = |raw[5:0];
    gaurd = raw[6];
    lsb = raw[7];
    kept = raw[14:7];

    round_up = gaurd && (sticky || lsb);
    result_temp = {1'b0, kept} + {1'b0, round_up};
    result = result_temp[8] ? '1 : result_temp[7:0];
    return result;

endfunction;


// Stage 0 input register
always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        valid_pipeline_reg <= '0;
        zero_check <= 1'b0;
    end else begin
        valid_pipeline_reg <= {valid_pipeline_reg[MAX_FL_MULT_DLY-2:0], valid_in};
        if(valid_in) begin
            a_reg <= a_in;
            b_reg <= b_in;
            zero_check <= (a_in.frac == 0 && a_in.exp == 0) || (b_in.frac == 0 && b_in.exp == 0);
        end
    end
end

// Stage 1 Comparators, Mantissa, and Exponent management
always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        zero_check_reg <= 1'b0;
    end else begin
        if(valid_pipeline_reg[REG_STAGE]) begin
            c_exp_raw <= {1'b0, a_reg.exp} + {1'b0, b_reg.exp}; //Q0.8 + Q0.8 = Q1.8
            c_mantissa_raw <= {1'b1, a_reg.frac} * {1'b1, b_reg.frac}; //Q1.7 * Q1.7 = Q2.14 (value can only be between 1 and 3.99999)
            c_sign_raw <= a_reg.sign ^ b_reg.sign;
        end
        zero_check_reg <= zero_check;
    end
end

// Stage 2 Normalize mantissa/exponent
always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        zero_check_reg2 <= 1'b0;
    end else begin
        zero_check_reg2 <= zero_check_reg;
        if(valid_pipeline_reg[COMP_STAGE]) begin
            c_sign_algn <= c_sign_raw;
            if(c_mantissa_raw[15]) begin
                c_mantissa_algn <= c_mantissa_raw >> 1;
                c_exp_algn <= c_exp_raw + 1; // Will not overflow since we already added gaurd bit previously
            end else begin
                c_mantissa_algn <= c_mantissa_raw;
                c_exp_algn <= c_exp_raw;
            end
        end
    end
end

assign mantissa_round = round_to_nearest_even(c_mantissa_algn[14:0]);

// Stage 2 Normalize mantissa/exponent
always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        valid_out <= 1'b0;
    end else begin
        valid_out <= valid_pipeline_reg[ALIGN_STAGE];
        if(valid_pipeline_reg[ALIGN_STAGE]) begin
            if(zero_check_reg2) begin
                c_out.exp <= '0;
                c_out.frac <= '0;
                c_out.sign <= 1'b0;
                overflow <= 1'b0;
            end else begin
                c_out.exp <= c_exp_algn[7:0];
                c_out.frac <= mantissa_round[6:0];
                c_out.sign <= c_sign_algn;
                overflow <= c_exp_algn[8];
            end
        end
    end
end

endmodule