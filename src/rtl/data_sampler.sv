module data_sampler #(
    parameter int DATA_W = 32
)(
    input  logic                 fast_clk,
    input  logic                 slow_clk,
    input  logic                 rst,        // active-low reset

    input  logic                 valid_i,
    input  logic [DATA_W-1:0]     data_i,

    output logic                 valid_o,     // 1-cycle pulse in slow_clk
    output logic [DATA_W-1:0]     data_o
);

    // ------------------------------------------------------------------
    // CDC control signals
    // ------------------------------------------------------------------
    logic req_fast;                 // request from fast domain
    logic req_fast_q, req_fast_2q;  // synchronized into slow domain

    logic ack_slow;                 // acknowledge from slow domain
    logic ack_q, ack_2q;            // synchronized into fast domain

    // ------------------------------------------------------------------
    // Data path
    // ------------------------------------------------------------------
    logic [DATA_W-1:0] fast_data_reg;

    // ------------------------------------------------------------------
    // State encoding
    // ------------------------------------------------------------------
    typedef enum logic {
        ST_FAST_IDLE,
        ST_FAST_HOLD
    } state_fast_e;

    typedef enum logic {
        ST_SLOW_IDLE,
        ST_SLOW_ACK
    } state_slow_e;

    state_fast_e curr_state_fast, next_state_fast;
    state_slow_e curr_state_slow, next_state_slow;

    // ------------------------------------------------------------------
    // FAST clock domain
    // ------------------------------------------------------------------

    // State register + CDC synchronizer
    always_ff @(posedge fast_clk or negedge rst) begin
        if (!rst) begin
            curr_state_fast <= ST_FAST_IDLE;
            ack_q           <= 1'b0;
            ack_2q          <= 1'b0;
            fast_data_reg   <= '0;
        end else begin
            curr_state_fast <= next_state_fast;
            ack_q           <= ack_slow;
            ack_2q          <= ack_q;

            // Capture data only when accepting new input
            if (curr_state_fast == ST_FAST_IDLE && valid_i)
                fast_data_reg <= data_i;
        end
    end

    // Next-state logic (fast domain)
    always_comb begin
        next_state_fast = curr_state_fast;
        req_fast        = 1'b0;

        case (curr_state_fast)
            ST_FAST_IDLE: begin
                if (valid_i) begin
                    req_fast        = 1'b1;
                    next_state_fast = ST_FAST_HOLD;
                end
            end

            ST_FAST_HOLD: begin
                req_fast = 1'b1;
                if (ack_2q)
                    next_state_fast = ST_FAST_IDLE;
            end

            default: begin
                next_state_fast = ST_FAST_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------------
    // SLOW clock domain
    // ------------------------------------------------------------------

    // State register + CDC synchronizer
    always_ff @(posedge slow_clk or negedge rst) begin
        if (!rst) begin
            curr_state_slow <= ST_SLOW_IDLE;
            req_fast_q      <= 1'b0;
            req_fast_2q     <= 1'b0;
        end else begin
            curr_state_slow <= next_state_slow;
            req_fast_q      <= req_fast;
            req_fast_2q     <= req_fast_q;
        end
    end

    // Next-state logic (slow domain)
    always_comb begin
        next_state_slow = curr_state_slow;
        ack_slow        = 1'b0;

        case (curr_state_slow)
            ST_SLOW_IDLE: begin
                if (req_fast_2q) begin
                    ack_slow        = 1'b1;  // single-cycle pulse
                    next_state_slow = ST_SLOW_ACK;
                end
            end

            ST_SLOW_ACK: begin
                next_state_slow = ST_SLOW_IDLE;
            end

            default: begin
                next_state_slow = ST_SLOW_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------------
    // Outputs (slow domain)
    // ------------------------------------------------------------------
    assign valid_o = ack_slow;
    assign data_o  = fast_data_reg;

endmodule
