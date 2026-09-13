module cic_round #(
    parameter int IN_WIDTH   = 29,
    parameter int OUT_WIDTH  = 20,
    parameter int ROUND_MODE = 0
) (
    input  logic                       clk          ,
    input  logic                       rst_n        ,

    input  logic signed [IN_WIDTH-1:0] i_din        ,
    input  logic                       i_din_valid  ,

    output logic signed [OUT_WIDTH-1:0] o_dout      ,
    output logic                        o_dout_valid
);

    // Round mode (0 - truncation, 1 - to +inf, 2 - to zero)
    localparam int ROUND_TRUNC   = 0;
    localparam int ROUND_POS_INF = 1;
    localparam int ROUND_TO_ZERO = 2;

    localparam int SHIFT = IN_WIDTH - OUT_WIDTH;


    generate

        if (IN_WIDTH > OUT_WIDTH) begin : gen_rounding

            logic signed [OUT_WIDTH-1:0] trunc_value  ;
            logic signed [OUT_WIDTH-1:0] rounded_value;

            logic remainder_nonzero;

            always_comb begin

                trunc_value = $signed(i_din) >>> SHIFT;

                remainder_nonzero = |i_din[SHIFT-1:0];


                case (ROUND_MODE)

                    // 0. truncation
                    ROUND_TRUNC: begin

                        rounded_value = trunc_value;

                    end

                    // 1. to +inf
                    ROUND_POS_INF: begin

                        if (remainder_nonzero)
                            rounded_value = trunc_value + $signed({{(OUT_WIDTH-1){1'b0}}, 1'b1});
                        else
                            rounded_value = trunc_value;

                    end

                    // 2. to zero
                    ROUND_TO_ZERO: begin

                        if (i_din[IN_WIDTH-1] && remainder_nonzero)
                            rounded_value = trunc_value + $signed({{(OUT_WIDTH-1){1'b0}}, 1'b1});
                        else
                            rounded_value = trunc_value;

                    end

                    default: begin

                        rounded_value = trunc_value;

                    end

                endcase

            end

            always_ff @(posedge clk or negedge rst_n) begin

                if (!rst_n) begin

                    o_dout       <=   '0;
                    o_dout_valid <= 1'b0;

                end else begin

                    o_dout_valid <= i_din_valid;

                    if (i_din_valid)
                        o_dout <= rounded_value;

                end

            end

        end

        else begin : gen_no_reduction

            always_ff @(posedge clk or negedge rst_n) begin

                if (!rst_n) begin

                    o_dout       <=   '0;
                    o_dout_valid <= 1'b0;

                end else begin

                    o_dout_valid <= i_din_valid;

                    if (i_din_valid)
                        o_dout <= $signed(i_din);

                end

            end

        end

    endgenerate

endmodule