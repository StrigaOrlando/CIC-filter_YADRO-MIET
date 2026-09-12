module cic_decimator_top #(
    parameter IN_WIDTH = 20,
    parameter OUT_WIDTH = 20,
    parameter R = 8,
    parameter M = 1,
    parameter N = 3,
    parameter OUTPUT_MODE = 0,
    parameter ROUND_MODE = 0,
    parameter NORMALIZE = 0
) (
    input  logic i_clk,
    input  logic i_rst_n,

    input  logic [((IN_WIDTH+7)/8)*8-1:0]  i_din_tdata,
    input  logic                           i_din_vld,
    output logic                           o_din_tready,

    output logic [((OUT_WIDTH+7)/8)*8-1:0] o_dout_tdata,
    output logic                           o_dout_vld,
    input  logic                           i_dout_tready
);

    localparam LOG2_RM    = $clog2(R * M);
    localparam GROWTH_W   = (N * LOG2_RM) + (((R*M) != (2**LOG2_RM)) ? 1 : 0);
    localparam FULL_WIDTH = IN_WIDTH + GROWTH_W;

    localparam GAIN       = (R * M) ** N;

    localparam ACTUAL_OUT_WIDTH = (OUTPUT_MODE == 1) ? OUT_WIDTH :
                                  (NORMALIZE) ? (FULL_WIDTH - $clog2(GAIN)) : FULL_WIDTH;

    localparam TDATA_IN_W  = ((IN_WIDTH  + 7) / 8) * 8;
    localparam TDATA_OUT_W = ((OUT_WIDTH + 7) / 8) * 8;

    logic signed [FULL_WIDTH-1:0] int_dout [0:N];
    logic                         int_vld [0:N];

    logic signed [FULL_WIDTH-1:0] dec_dout;
    logic                         dec_vld;

    logic signed [FULL_WIDTH-1:0] comb_dout [0:N];
    logic                         comb_vld [0:N];

    logic signed [FULL_WIDTH-1:0] norm_dout;
    logic                         norm_vld;

    logic signed [ACTUAL_OUT_WIDTH-1:0] round_dout;
    logic                               round_vld;

    assign o_din_tready = 1'b1;

    logic signed [IN_WIDTH-1:0] din_data;
    assign din_data = IN_WIDTH'(i_din_tdata[IN_WIDTH-1:0]);

    assign int_dout[0]  = din_data;
    assign int_vld[0] = i_din_vld;

    generate
        genvar i;
        for (i = 0; i < N; i = i + 1) begin : gen_integrators
            localparam INT_IN_W  = (i == 0) ? IN_WIDTH : FULL_WIDTH;
            localparam INT_ACC_W = FULL_WIDTH;

            cic_int #(
                .IN_WIDTH  (INT_IN_W),
                .ACC_WIDTH (INT_ACC_W)
            ) u_int (
                .clk        (i_clk),
                .rst_n      (i_rst_n),
                .i_din      (int_dout[i][INT_IN_W-1:0]),
                .i_din_valid (int_vld[i]),
                .o_dout     (int_dout[i+1]),
                .o_dout_valid (int_vld[i+1])
            );
        end
    endgenerate

    cic_dec #(
        .DATA_WIDTH (FULL_WIDTH),
        .R          (R)
    ) u_dec (
        .clk        (i_clk),
        .rst_n      (i_rst_n),
        .i_din      (int_dout[N]),
        .i_din_valid (int_vld[N]),
        .o_dout     (dec_dout),
        .o_dout_valid (dec_vld)
    );

    assign comb_dout[0]  = dec_dout;
    assign comb_vld[0] = dec_vld;

    generate
        genvar j;
        for (j = 0; j < N; j = j + 1) begin : gen_combs
            cic_comb #(
                .IN_WIDTH  (FULL_WIDTH),
                .OUT_WIDTH (FULL_WIDTH),
                .M         (M)
            ) u_comb (
                .clk        (i_clk),
                .rst_n      (i_rst_n),
                .i_din      (comb_dout[j]),
                .i_din_valid (comb_vld[j]),
                .o_dout     (comb_dout[j+1]),
                .o_dout_valid (comb_vld[j+1])
            );
        end
    endgenerate

    generate
        if (NORMALIZE) begin : gen_normalize
            cic_normalize #(
                .DATA_WIDTH (FULL_WIDTH),
                .R          (R),
                .M          (M),
                .N          (N)
            ) u_norm (
                .clk        (i_clk),
                .rst_n      (i_rst_n),
                .i_din      (comb_dout[N]),
                .i_din_valid (comb_vld[N]),
                .o_dout     (norm_dout),
                .o_dout_valid (norm_vld)
            );
        end else begin : gen_no_normalize
            assign norm_dout  = comb_dout[N];
            assign norm_vld = comb_vld[N];
        end
    endgenerate

    generate
        if (OUTPUT_MODE == 1) begin : gen_round
            cic_round #(
                .IN_WIDTH   (FULL_WIDTH),
                .OUT_WIDTH  (ACTUAL_OUT_WIDTH),
                .ROUND_MODE (ROUND_MODE)
            ) u_round (
                .clk        (i_clk),
                .rst_n      (i_rst_n),
                .i_din      (norm_dout),
                .i_din_valid (norm_vld),
                .o_dout     (round_dout),
                .o_dout_valid (round_vld)
            );
        end else begin : gen_full
            assign round_dout  = ACTUAL_OUT_WIDTH'(norm_dout);
            assign round_vld = norm_vld;
        end
    endgenerate

    generate
        if (ACTUAL_OUT_WIDTH >= TDATA_OUT_W) begin : gen_wide_out
            assign o_dout_tdata = TDATA_OUT_W'(round_dout);
        end else begin : gen_narrow_out
            assign o_dout_tdata = {{(TDATA_OUT_W - ACTUAL_OUT_WIDTH){round_dout[ACTUAL_OUT_WIDTH-1]}},
                                   round_dout};
        end
    endgenerate

    assign o_dout_vld = round_vld;

endmodule