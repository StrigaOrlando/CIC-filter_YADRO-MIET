module cic_normalize #(
    parameter int IN_WIDTH                          = 21                ,
    parameter int OUT_WIDTH                         = 12                ,
    parameter int ROUND_MODE                        = 0                 ,
    parameter int FRAC_BITS                         = 20                ,
    parameter int TERM_COUNT                        = 1                 ,
    parameter int signed CSD_SHIFT [0:TERM_COUNT-1] = '{0:11, default:0},
    parameter bit CSD_NEGATIVE [0:TERM_COUNT-1]     = '{0:0, default:0}
) (
    input  logic                        clk          ,
    input  logic                        rst_n        ,
    input  logic signed [IN_WIDTH-1:0]  i_din        ,
    input  logic                        i_din_valid  ,
    output logic signed [OUT_WIDTH-1:0] o_dout       ,
    output logic                        o_dout_valid
);
    function automatic int max_term_shift();
        int m;
        m = 0;
        for (int k = 0; k < TERM_COUNT; k++)
            if (CSD_SHIFT[k] > m) m = CSD_SHIFT[k];
        return m;
    endfunction

    localparam int SAFE_TERMS  = (TERM_COUNT > 0) ? TERM_COUNT : 1      ;
    localparam int TREE_LEVELS = $clog2(SAFE_TERMS)                     ;
    localparam int PAD_TERMS   = (1 << TREE_LEVELS)                     ;
    localparam int MAX_SHIFT   = max_term_shift()                       ;
    localparam int SUM_W_A     = IN_WIDTH + MAX_SHIFT + TREE_LEVELS + 2 ;
    localparam int SUM_W_B     = FRAC_BITS + OUT_WIDTH + 2              ;
    localparam int SUM_WIDTH   = (SUM_W_A > SUM_W_B) ? SUM_W_A : SUM_W_B;

    logic signed [SUM_WIDTH-1:0] x_extended                         ;
    logic signed [SUM_WIDTH-1:0] tree [0:TREE_LEVELS][0:PAD_TERMS-1];
    logic signed [SUM_WIDTH-1:0] floor_value                        ;
    logic signed [SUM_WIDTH-1:0] rounded_value                      ;
    logic fractional_nonzero                                        ;

    assign x_extended = $signed(i_din);

    generate
        for (genvar k = 0; k < PAD_TERMS; k++) begin : gen_csd_leaf
            if (k < TERM_COUNT) begin : gen_active
                if (CSD_NEGATIVE[k]) begin : gen_minus
                    assign tree[0][k] = -(x_extended <<< CSD_SHIFT[k]);
                end else begin : gen_plus
                    assign tree[0][k] =  (x_extended <<< CSD_SHIFT[k]);
                end
            end else begin : gen_padding
                assign tree[0][k] = '0;
            end
        end
        for (genvar level = 0; level < TREE_LEVELS; level++) begin : gen_csd_tree
            for (genvar k = 0; k < PAD_TERMS; k++) begin : gen_nodes
                if (k < (PAD_TERMS >> (level+1))) begin : gen_add
                    assign tree[level+1][k] =
                        tree[level][2*k] + tree[level][2*k+1];
                end else begin : gen_unused
                    assign tree[level+1][k] = '0;
                end
            end
        end
    endgenerate

    generate
        if (FRAC_BITS > 0 && FRAC_BITS < SUM_WIDTH) begin : gen_fractional
            assign floor_value = $signed(tree[TREE_LEVELS][0]) >>> FRAC_BITS;
            assign fractional_nonzero = |tree[TREE_LEVELS][0][FRAC_BITS-1:0];
        end else begin : gen_integer
            assign floor_value = $signed(tree[TREE_LEVELS][0]);
            assign fractional_nonzero = 1'b0                  ;
        end
    endgenerate

    always_comb begin
        rounded_value = floor_value;
        case (ROUND_MODE)
            1: if (fractional_nonzero)
                   rounded_value = floor_value + SUM_WIDTH'(1);  // 1 - to +inf
            2: if (tree[TREE_LEVELS][0][SUM_WIDTH-1] && fractional_nonzero)
                   rounded_value = floor_value + SUM_WIDTH'(1);  // 2 - to zero
            default: ; // 0 - truncation
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_dout       <= '0  ;
            o_dout_valid <= 1'b0;
        end else begin
            o_dout_valid <= i_din_valid;
            if (i_din_valid)
                o_dout <= rounded_value;
        end
    end

endmodule : cic_normalize
