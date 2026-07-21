`timescale 1ns / 1ps

// Топ-модуль

module cic_decimator_top #(
    parameter IN_WIDTH   = cic_parameters_pkg::IN_WIDTH,
    parameter OUT_WIDTH  = cic_parameters_pkg::FULL_WIDTH,
    parameter R          = cic_parameters_pkg::R,
    parameter M          = cic_parameters_pkg::M,
    parameter N          = cic_parameters_pkg::N,
    parameter OUTPUT_MODE = cic_parameters_pkg::OUTPUT_MODE,
    parameter ROUND_MODE  = cic_parameters_pkg::ROUND_MODE,
    parameter NORMALIZE   = cic_parameters_pkg::NORMALIZE
) (
    input  logic clk,
    input  logic rst_n,

    input  logic [((IN_WIDTH+7)/8)*8-1:0]  s_din_tdata,
    input  logic                             s_din_tvalid,
    output logic                             s_din_tready,

    output logic [((OUT_WIDTH+7)/8)*8-1:0] m_dout_tdata,
    output logic                             m_dout_tvalid,
    input  logic                             m_dout_tready
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
    logic                         int_valid [0:N];

    logic signed [FULL_WIDTH-1:0] dec_dout;
    logic                         dec_valid;

    logic signed [FULL_WIDTH-1:0] comb_dout [0:N];
    logic                         comb_valid [0:N];

    logic signed [FULL_WIDTH-1:0] norm_dout;
    logic                         norm_valid;

    logic signed [ACTUAL_OUT_WIDTH-1:0] round_dout;
    logic                               round_valid;


    logic rst;
    assign rst = ~rst_n;

    assign s_din_tready = 1'b1;

    logic signed [IN_WIDTH-1:0] din_data;
    assign din_data = IN_WIDTH'(s_din_tdata[IN_WIDTH-1:0]);

    assign int_dout[0]  = din_data;
    assign int_valid[0] = s_din_tvalid;

    generate
        genvar i;
        for (i = 0; i < N; i = i + 1) begin : gen_integrators
            localparam INT_IN_W  = (i == 0) ? IN_WIDTH : FULL_WIDTH;
            localparam INT_ACC_W = FULL_WIDTH;

            cic_int #(
                .IN_WIDTH  (INT_IN_W),
                .ACC_WIDTH (INT_ACC_W)
            ) u_int (
                .clk        (clk),
                .rst        (rst),
                .din        (int_dout[i][INT_IN_W-1:0]),
                .din_valid  (int_valid[i]),
                .dout       (int_dout[i+1]),
                .dout_valid (int_valid[i+1])
            );
        end
    endgenerate

    cic_dec #(
        .DATA_WIDTH (FULL_WIDTH),
        .R          (R)
    ) u_dec (
        .clk        (clk),
        .rst        (rst),
        .din        (int_dout[N]),
        .din_valid  (int_valid[N]),
        .dout       (dec_dout),
        .dout_valid (dec_valid)
    );

    assign comb_dout[0]  = dec_dout;
    assign comb_valid[0] = dec_valid;

    generate
        genvar j;
        for (j = 0; j < N; j = j + 1) begin : gen_combs
            cic_comb #(
                .IN_WIDTH  (FULL_WIDTH),
                .OUT_WIDTH (FULL_WIDTH),
                .M         (M)
            ) u_comb (
                .clk        (clk),
                .rst        (rst),
                .din        (comb_dout[j]),
                .din_valid  (comb_valid[j]),
                .dout       (comb_dout[j+1]),
                .dout_valid (comb_valid[j+1])
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
                .clk        (clk),
                .rst        (rst),
                .din        (comb_dout[N]),
                .din_valid  (comb_valid[N]),
                .dout       (norm_dout),
                .dout_valid (norm_valid)
            );
        end else begin : gen_no_normalize
            assign norm_dout  = comb_dout[N];
            assign norm_valid = comb_valid[N];
        end
    endgenerate

    generate
        if (OUTPUT_MODE == 1) begin : gen_round
            cic_round #(
                .IN_WIDTH   (FULL_WIDTH),
                .OUT_WIDTH  (ACTUAL_OUT_WIDTH),
                .ROUND_MODE (ROUND_MODE)
            ) u_round (
                .clk        (clk),
                .rst        (rst),
                .din        (norm_dout),
                .din_valid  (norm_valid),
                .dout       (round_dout),
                .dout_valid (round_valid)
            );
        end else begin : gen_full
            assign round_dout  = ACTUAL_OUT_WIDTH'(norm_dout);
            assign round_valid = norm_valid;
        end
    endgenerate

    generate
        if (ACTUAL_OUT_WIDTH >= TDATA_OUT_W) begin : gen_wide_out
            assign m_dout_tdata = TDATA_OUT_W'(round_dout);
        end else begin : gen_narrow_out
            assign m_dout_tdata = {{(TDATA_OUT_W - ACTUAL_OUT_WIDTH){round_dout[ACTUAL_OUT_WIDTH-1]}},
                                   round_dout};
        end
    endgenerate

    assign m_dout_tvalid = round_valid;

endmodule
