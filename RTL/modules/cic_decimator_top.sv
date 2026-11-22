module cic_decimator_top #(
    parameter int IN_WIDTH                  = cic_parameters_pkg::IN_WIDTH                  ,
    parameter int OUT_WIDTH                 = cic_parameters_pkg::OUT_WIDTH                 ,
    parameter int R                         = cic_parameters_pkg::R                         ,
    parameter int M                         = cic_parameters_pkg::M                         ,
    parameter int N                         = cic_parameters_pkg::N                         ,
    parameter bit OUTPUT_MODE               = cic_parameters_pkg::OUTPUT_MODE               ,
    parameter int ROUND_MODE                = cic_parameters_pkg::ROUND_MODE                ,
    parameter bit NORMALIZE                 = cic_parameters_pkg::NORMALIZE                 ,
    parameter bit PRUNING_EN                = cic_parameters_pkg::PRUNING_EN                ,
    parameter int PRE_NORM_WIDTH            = cic_parameters_pkg::PRE_NORM_WIDTH            ,
    parameter int NUM_CHANNELS              = 1                                             ,
    parameter int TID_WIDTH                 = (NUM_CHANNELS <= 1) ? 1 : $clog2(NUM_CHANNELS),
    parameter bit COMP_AFR                  = cic_parameters_pkg::COMP_AFR                  ,
    parameter int COMP_L                    = cic_parameters_pkg::COMP_L                    ,
    parameter int COMP_COEFF_FRAC_BITS      = cic_parameters_pkg::COMP_COEFF_FRAC_BITS      ,
    parameter int signed COMP_COEFF_Q [0:3] = cic_parameters_pkg::COMP_COEFF_Q              ,
    parameter int COMP_GROWTH_W             = cic_parameters_pkg::COMP_GROWTH_W             ,
    parameter int NORM_FRAC_BITS            = cic_parameters_pkg::NORM_FRAC_BITS            ,
    parameter int NORM_CSD_TERM_COUNT       = cic_parameters_pkg::NORM_CSD_TERM_COUNT,
    parameter int NORM_CSD_SHIFT [0:NORM_CSD_TERM_COUNT-1] =
        cic_parameters_pkg::NORM_CSD_SHIFT,
    parameter bit NORM_CSD_NEGATIVE [0:NORM_CSD_TERM_COUNT-1] =
        cic_parameters_pkg::NORM_CSD_NEGATIVE,
    parameter int TDATA_OUT_W       =
      (((((OUTPUT_MODE == 0) ? OUT_WIDTH :
          ((NORMALIZE ? IN_WIDTH :
            cic_parameters_pkg::calc_full_width(IN_WIDTH,N,R,M)) +
           (COMP_AFR ? COMP_GROWTH_W : 0))) + 7) / 8) * 8)
) (
    input  logic                          i_clk         ,
    input  logic                          i_rst_n       ,
    input  logic [((IN_WIDTH+7)/8)*8-1:0] i_din_tdata   ,
    input  logic [TID_WIDTH-1:0]          i_din_tid     ,
    input  logic                          i_din_vld     ,
    output logic                          o_din_tready  ,
    output logic [TDATA_OUT_W-1:0]        o_dout_tdata  ,
    output logic [TID_WIDTH-1:0]          o_dout_tid    ,
    output logic                          o_dout_vld    ,
    input  logic                          i_dout_tready
);
    function automatic int stage_prune(input int j);
        if (!PRUNING_EN || j < 1 || j >= cic_parameters_pkg::STAGES)
            return 0;
        return cic_parameters_pkg::Bj[j];
    endfunction

    localparam int FULL_WIDTH      = cic_parameters_pkg::calc_full_width(IN_WIDTH,N,R,M);
    localparam int S_PRUNE         = stage_prune(2*N)                                   ;
    localparam int COMB_LAST_W     = FULL_WIDTH - S_PRUNE                               ;
    localparam int PRE_NORM_DATA_W =
        (NORMALIZE && PRE_NORM_WIDTH > 0 && PRE_NORM_WIDTH < COMB_LAST_W)
        ? PRE_NORM_WIDTH : COMB_LAST_W;
    localparam int S_PRE = COMB_LAST_W - PRE_NORM_DATA_W                                ;

    localparam int EFFECTIVE_WIDTH  = NORMALIZE ? IN_WIDTH : FULL_WIDTH               ;
    localparam int COMP_OUT_WIDTH   = EFFECTIVE_WIDTH + COMP_GROWTH_W                 ;
    localparam int POST_COMP_WIDTH  = COMP_AFR ? COMP_OUT_WIDTH : EFFECTIVE_WIDTH     ;
    localparam int ACTUAL_OUT_WIDTH = (OUTPUT_MODE == 0) ? OUT_WIDTH : POST_COMP_WIDTH;
    localparam int PRE_ACTIVE       = (NORMALIZE && S_PRE > 0) ? 1 : 0                ;
    localparam int PIPE_STAGES      = (2*N+1) + PRE_ACTIVE + (NORMALIZE ? 1 : 0)
                                + (COMP_AFR ? 1 : 0) + (OUTPUT_MODE == 0 ? 1 : 0);
    localparam int OUT_DEPTH = PIPE_STAGES + 2                                        ;
    localparam int PTR_W     = (OUT_DEPTH <= 1) ? 1 : $clog2(OUT_DEPTH)               ;
    localparam int CNT_W     = (OUT_DEPTH <= 1) ? 1 : $clog2(OUT_DEPTH+1)             ;

    logic signed [FULL_WIDTH-1:0] int_dout [0:N] ;
    logic [N:0] int_vld                          ;
    logic [TID_WIDTH-1:0] int_tid [0:N]          ;
    logic signed [FULL_WIDTH-1:0] dec_dout       ;
    logic dec_vld                                ;
    logic [TID_WIDTH-1:0] dec_tid                ;
    logic signed [FULL_WIDTH-1:0] comb_dout [0:N];
    logic [N:0] comb_vld                         ;
    logic [TID_WIDTH-1:0] comb_tid [0:N]         ;

    logic signed [COMB_LAST_W-1:0] pre_norm_dout          ;
    logic pre_norm_vld                                    ;
    logic [TID_WIDTH-1:0] pre_norm_tid                    ;
    logic signed [EFFECTIVE_WIDTH-1:0] norm_dout          ;
    logic norm_vld                                        ;
    logic [TID_WIDTH-1:0] norm_tid                        ;
    logic signed [POST_COMP_WIDTH-1:0] comp_dout          ;
    logic comp_vld                                        ;
    logic [TID_WIDTH-1:0] comp_tid                        ;
    logic signed [EFFECTIVE_WIDTH-1:0] comp_effective_dout;
    logic signed [ACTUAL_OUT_WIDTH-1:0] round_dout        ;
    logic round_vld                                       ;
    logic [TID_WIDTH-1:0] round_tid                       ;
    logic [TDATA_OUT_W-1:0] packed_result                 ;
    logic [PIPE_STAGES-1:0] token_pipe_ff                 ;
    logic [CNT_W-1:0] credits_used_ff                     ;
    logic [CNT_W-1:0] credits_next                        ;
    logic [CNT_W-1:0] out_count_ff                        ;
    logic [PTR_W-1:0] out_wr_ptr_ff, out_rd_ptr_ff        ;
    (* ram_style = "distributed" *)
    logic [TDATA_OUT_W+TID_WIDTH-1:0] out_mem [0:OUT_DEPTH-1]           ;
    logic input_fire, output_pop, output_push, retire_token, retire_drop;
    logic tid_ok                                                        ;

    assign tid_ok = (NUM_CHANNELS <= 1) ? (i_din_tid == '0) : (i_din_tid < NUM_CHANNELS);
    assign o_din_tready = i_rst_n && tid_ok && (credits_used_ff < OUT_DEPTH)            ;
    assign input_fire = i_din_vld && o_din_tready                                       ;
    assign retire_token = token_pipe_ff[PIPE_STAGES-1]                                  ;
    assign output_push = round_vld                                                      ;
    assign retire_drop = retire_token && !output_push                                   ;
    assign o_dout_vld = (out_count_ff != 0)                                             ;
    assign output_pop = o_dout_vld && i_dout_tready                                     ;
    assign {o_dout_tid, o_dout_tdata} = o_dout_vld ? out_mem[out_rd_ptr_ff] : '0        ;

    always_comb begin
        credits_next = credits_used_ff;
        if (input_fire) credits_next = credits_next + 1'b1;
        if (output_pop) credits_next = credits_next - 1'b1;
        if (retire_drop) credits_next = credits_next - 1'b1;
    end

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            token_pipe_ff   <= '0;
            credits_used_ff <= '0;
            out_count_ff    <= '0;
            out_wr_ptr_ff   <= '0;
            out_rd_ptr_ff   <= '0;
        end else begin
            token_pipe_ff   <= (token_pipe_ff << 1) | PIPE_STAGES'(input_fire);
            credits_used_ff <= credits_next                                   ;
            if (output_push) begin
                out_mem[out_wr_ptr_ff] <= {round_tid, packed_result};
                if (out_wr_ptr_ff == OUT_DEPTH-1) out_wr_ptr_ff <= '0;
                else out_wr_ptr_ff <= out_wr_ptr_ff + 1'b1;
            end
            if (output_pop) begin
                if (out_rd_ptr_ff == OUT_DEPTH-1) out_rd_ptr_ff <= '0;
                else out_rd_ptr_ff <= out_rd_ptr_ff + 1'b1;
            end
            case ({output_push, output_pop})
                2'b10: out_count_ff <= out_count_ff + 1'b1;
                2'b01: out_count_ff <= out_count_ff - 1'b1;
                default: ;
            endcase
        end
    end

    logic signed [IN_WIDTH-1:0] din_data                 ;
    logic [TID_WIDTH-1:0] din_tid                        ;
    assign din_data = $signed(i_din_tdata[IN_WIDTH-1:0]) ;
    assign din_tid = (NUM_CHANNELS <= 1) ? '0 : i_din_tid;
    assign int_dout[0] = din_data                        ;
    assign int_vld[0] = input_fire                       ;
    assign int_tid[0] = din_tid                          ;

    generate
        for (genvar i = 0; i < N; i++) begin : gen_integrators
            localparam int IN_S = (i == 0) ? 0 : stage_prune(i)             ;
            localparam int OUT_S     = stage_prune(i+1)                     ;
            localparam int INT_IN_W  = (i == 0) ? IN_WIDTH : FULL_WIDTH-IN_S;
            localparam int INT_ACC_W = FULL_WIDTH-OUT_S                     ;
            logic signed [INT_ACC_W-1:0] stage_dout                         ;
            cic_int #(
                .IN_WIDTH     (INT_IN_W)    ,
                .ACC_WIDTH    (INT_ACC_W)   ,
                .IN_SCALE     (IN_S)        ,
                .ACC_SCALE    (OUT_S)       ,
                .NUM_CHANNELS (NUM_CHANNELS),
                .TID_WIDTH    (TID_WIDTH)
            ) u_int (
                .clk          (i_clk)                    ,
                .rst_n        (i_rst_n)                  ,
                .i_din        (int_dout[i][INT_IN_W-1:0]),
                .i_din_valid  (int_vld[i])               ,
                .i_tid        (int_tid[i])               ,
                .o_dout       (stage_dout)               ,
                .o_dout_valid (int_vld[i+1])
            );
            assign int_dout[i+1] = stage_dout;
            always_ff @(posedge i_clk or negedge i_rst_n)
                if (!i_rst_n) int_tid[i+1] <= '0;
                else if (int_vld[i]) int_tid[i+1] <= int_tid[i];
        end
    endgenerate

    localparam int LAST_INT_W = FULL_WIDTH - stage_prune(N);
    cic_dec #(
        .DATA_WIDTH(LAST_INT_W),
    .R            (R)           ,
    .NUM_CHANNELS (NUM_CHANNELS),
    .TID_WIDTH    (TID_WIDTH)
) u_dec (
        .clk          (i_clk)                      ,
        .rst_n        (i_rst_n)                    ,
        .i_din        (int_dout[N][LAST_INT_W-1:0]),
        .i_din_valid  (int_vld[N])                 ,
        .i_tid        (int_tid[N])                 ,
        .o_dout       (dec_dout)                   ,
        .o_dout_valid (dec_vld)
    );
    always_ff @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) dec_tid <= '0;
        else if (int_vld[N]) dec_tid <= int_tid[N];
    assign comb_dout[0] = dec_dout;
    assign comb_vld[0] = dec_vld  ;
    assign comb_tid[0] = dec_tid  ;

    generate
        for (genvar j = 0; j < N; j++) begin : gen_combs
            localparam int IN_S       = stage_prune(N+j)  ;
            localparam int OUT_S      = stage_prune(N+j+1);
            localparam int COMB_IN_W  = FULL_WIDTH-IN_S   ;
            localparam int COMB_OUT_W = FULL_WIDTH-OUT_S  ;
            logic signed [COMB_OUT_W-1:0] stage_dout      ;
            cic_comb #(
                .IN_WIDTH(COMB_IN_W),
            .OUT_WIDTH    (COMB_OUT_W)  ,
            .IN_SCALE     (IN_S)        ,
            .OUT_SCALE    (OUT_S)       ,
            .M            (M)           ,
            .NUM_CHANNELS (NUM_CHANNELS),
            .TID_WIDTH    (TID_WIDTH)
        ) u_comb (
                .clk          (i_clk)                      ,
                .rst_n        (i_rst_n)                    ,
                .i_din        (comb_dout[j][COMB_IN_W-1:0]),
                .i_din_valid  (comb_vld[j])                ,
                .i_tid        (comb_tid[j])                ,
                .o_dout       (stage_dout)                 ,
                .o_dout_valid (comb_vld[j+1])
            );
            assign comb_dout[j+1] = stage_dout;
            always_ff @(posedge i_clk or negedge i_rst_n)
                if (!i_rst_n) comb_tid[j+1] <= '0;
                else if (comb_vld[j]) comb_tid[j+1] <= comb_tid[j];
        end
    endgenerate

    logic signed [FULL_WIDTH-1:0] comb_full_ext                  ;
    logic signed [FULL_WIDTH-1:0] comb_unpruned_scale            ;
    assign comb_full_ext = $signed(comb_dout[N][COMB_LAST_W-1:0]);
    assign comb_unpruned_scale = comb_full_ext <<< S_PRUNE       ;
    generate
        if (PRE_ACTIVE) begin : gen_pre_normalize
            logic signed [PRE_NORM_DATA_W-1:0] narrowed;
            cic_round #(
                .IN_WIDTH(COMB_LAST_W),
            .OUT_WIDTH  (PRE_NORM_DATA_W) ,
            .ROUND_MODE (ROUND_MODE)
        ) u_pre_round (
                .clk          (i_clk)                        ,
                .rst_n        (i_rst_n)                      ,
                .i_din        (comb_dout[N][COMB_LAST_W-1:0]),
                .i_din_valid  (comb_vld[N])                  ,
                .o_dout       (narrowed)                     ,
                .o_dout_valid (pre_norm_vld)
            );
            assign pre_norm_dout = narrowed;
            always_ff @(posedge i_clk or negedge i_rst_n)
                if (!i_rst_n) pre_norm_tid <= '0;
                else if (comb_vld[N]) pre_norm_tid <= comb_tid[N];
        end else begin : gen_no_pre_normalize
            assign pre_norm_dout = comb_dout[N][COMB_LAST_W-1:0] ;
            assign pre_norm_vld = comb_vld[N]                    ;
            assign pre_norm_tid = comb_tid[N]                    ;
        end
    endgenerate

    generate
        if (NORMALIZE) begin : gen_normalize
            cic_normalize #(
                .IN_WIDTH     (PRE_NORM_DATA_W)    ,
                .OUT_WIDTH    (IN_WIDTH)           ,
                .ROUND_MODE   (ROUND_MODE)         ,
                .FRAC_BITS    (NORM_FRAC_BITS)     ,
                .TERM_COUNT   (NORM_CSD_TERM_COUNT),
                .CSD_SHIFT    (NORM_CSD_SHIFT)     ,
                .CSD_NEGATIVE (NORM_CSD_NEGATIVE)
            ) u_norm (
                .clk          (i_clk)        ,
                .rst_n        (i_rst_n)      ,
                .i_din        (pre_norm_dout),
                .i_din_valid  (pre_norm_vld) ,
                .o_dout       (norm_dout)    ,
                .o_dout_valid (norm_vld)
            );
            always_ff @(posedge i_clk or negedge i_rst_n)
                if (!i_rst_n) norm_tid <= '0;
                else if (pre_norm_vld) norm_tid <= pre_norm_tid;
        end else begin : gen_no_normalize
            assign norm_dout = comb_unpruned_scale;
            assign norm_vld = comb_vld[N]         ;
            assign norm_tid = comb_tid[N]         ;
        end
    endgenerate

    generate
        if (COMP_AFR) begin : gen_fir_comp
            cic_fir_comp #(
                .IN_WIDTH        (EFFECTIVE_WIDTH)     ,
                .OUT_WIDTH       (COMP_OUT_WIDTH)      ,
                .L               (COMP_L)              ,
                .COEFF_FRAC_BITS (COMP_COEFF_FRAC_BITS),
                .COEFF_Q         (COMP_COEFF_Q)        ,
                .NUM_CHANNELS    (NUM_CHANNELS)        ,
                .TID_WIDTH       (TID_WIDTH)
            ) u_fir_comp (
                .clk          (i_clk)    ,
                .rst_n        (i_rst_n)  ,
                .i_din        (norm_dout),
                .i_din_valid  (norm_vld) ,
                .i_tid        (norm_tid) ,
                .o_dout       (comp_dout),
                .o_dout_valid (comp_vld)
            );
            always_ff @(posedge i_clk or negedge i_rst_n)
                if (!i_rst_n) comp_tid <= '0;
                else if (norm_vld) comp_tid <= norm_tid;
        end else begin : gen_no_fir_comp
            assign comp_dout = norm_dout;
            assign comp_vld = norm_vld  ;
            assign comp_tid = norm_tid  ;
        end
    endgenerate
    assign comp_effective_dout = comp_dout[EFFECTIVE_WIDTH-1:0];
    generate
        if (OUTPUT_MODE == 0) begin : gen_round
            cic_round #(
                .IN_WIDTH(EFFECTIVE_WIDTH),
            .OUT_WIDTH  (ACTUAL_OUT_WIDTH) ,
            .ROUND_MODE (ROUND_MODE)
        ) u_round (
                .clk          (i_clk)              ,
                .rst_n        (i_rst_n)            ,
                .i_din        (comp_effective_dout),
                .i_din_valid  (comp_vld)           ,
                .o_dout       (round_dout)         ,
                .o_dout_valid (round_vld)
            );
            always_ff @(posedge i_clk or negedge i_rst_n)
                if (!i_rst_n) round_tid <= '0;
                else if (comp_vld) round_tid <= comp_tid;
        end else begin : gen_full
            assign round_dout = ACTUAL_OUT_WIDTH'(comp_dout);
            assign round_vld = comp_vld                     ;
            assign round_tid = comp_tid                     ;
        end
    endgenerate

    assign packed_result = $signed(round_dout);
endmodule : cic_decimator_top
