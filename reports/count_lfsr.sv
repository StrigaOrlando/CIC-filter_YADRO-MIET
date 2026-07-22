`timescale 1ns/1ps

module count_lfsr #(
    parameter int R = 1023
) (
    input logic clk,
    input logic rst,
    input logic enable,

    output logic tick
);

    initial begin
        if (R < 1) begin
            $error("R must be >= 1");
        end

        if (R > 1023) begin
            $error("R must be <= 1023");
        end
    end

    localparam int LFSR_WIDTH = (R <= 2) ? 2 : $clog2(R + 1);

    function automatic logic [LFSR_WIDTH-1:0] get_tap_mask(input int width);
        begin
            case (width)
                2:  get_tap_mask = 2'b11;
                3:  get_tap_mask = 3'b101;
                4:  get_tap_mask = 4'b1001;
                5:  get_tap_mask = 5'b10010;
                6:  get_tap_mask = 6'b100001;
                7:  get_tap_mask = 7'b1000001;
                8:  get_tap_mask = 8'b10001110;
                9:  get_tap_mask = 9'b100001000;
                10: get_tap_mask = 10'b1000000100;
                default: get_tap_mask = '0;
            endcase
        end
    endfunction

    localparam logic [LFSR_WIDTH-1:0] TAP_MASK = get_tap_mask(LFSR_WIDTH);

    localparam logic [LFSR_WIDTH-1:0] LFSR_SEED = {{(LFSR_WIDTH-1){1'b0}}, 1'b1};

    function automatic logic [LFSR_WIDTH-1:0] lfsr_step(input logic [LFSR_WIDTH-1:0] state);
        logic feedback;

        begin
            feedback = ^(state & TAP_MASK);

            lfsr_step = {state[LFSR_WIDTH-2:0],feedback};
        end
    endfunction

    function automatic logic [LFSR_WIDTH-1:0] calc_terminal_state(input int steps);
        logic [LFSR_WIDTH-1:0] state;

        begin
            state = LFSR_SEED;

            for (int i = 0; i < steps; i = i + 1) begin
                state = lfsr_step(state);
            end

            calc_terminal_state = state;
        end
    endfunction

    localparam logic [LFSR_WIDTH-1:0] TERM_STATE = calc_terminal_state(R - 1);

    logic [LFSR_WIDTH-1:0] lfsr_q;
    logic [LFSR_WIDTH-1:0] lfsr_w;

    assign lfsr_w = lfsr_step(lfsr_q);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr_q <= LFSR_SEED;
            tick <= 1'b0;
        end else begin
            tick <= 1'b0;

            if (enable) begin
                if ((R == 1) || (lfsr_q == TERM_STATE)) begin

                    lfsr_q <= LFSR_SEED;
                    tick <= 1'b1;
                end else begin
                    lfsr_q <= lfsr_w;
                end
            end
        end
    end

endmodule
