module cic_comb #(
    parameter int IN_WIDTH     = 24,
    parameter int OUT_WIDTH    = 24,
    parameter int IN_SCALE     = 0 ,
    parameter int OUT_SCALE    = 0 ,
    parameter int M            = 1 ,
    parameter int NUM_CHANNELS = 1 ,
    parameter int TID_WIDTH    = (NUM_CHANNELS <= 1) ? 1 : $clog2(NUM_CHANNELS)
) (
    input  logic                            clk          ,
    input  logic                            rst_n        ,

    input  logic signed [IN_WIDTH  - 1 : 0] i_din        ,
    input  logic                            i_din_valid  ,
    input  logic        [TID_WIDTH - 1 : 0] i_tid        ,

    output logic signed [OUT_WIDTH - 1 : 0] o_dout       ,
    output logic                            o_dout_valid
);
    localparam int FULL_SCALE_W = ((IN_WIDTH + IN_SCALE) > (OUT_WIDTH + OUT_SCALE))
                                ? (IN_WIDTH + IN_SCALE) : (OUT_WIDTH + OUT_SCALE);
    logic signed [OUT_WIDTH-1:0] delay_q_ff [0:NUM_CHANNELS-1][0:M-1];
    logic signed [FULL_SCALE_W-1:0] in_ext, in_full                  ;
    logic signed [OUT_WIDTH-1:0] din_aligned                         ;

    assign in_ext = $signed(i_din)                     ;
    assign in_full = in_ext <<< IN_SCALE               ;
    assign din_aligned = $signed(in_full) >>> OUT_SCALE;
    logic signed [OUT_WIDTH - 1 : 0] dout_ff           ;
    logic signed [OUT_WIDTH - 1 : 0] dout_next         ;

    logic dout_valid_ff                ;
    logic dout_valid_next              ;
    logic [TID_WIDTH - 1 : 0] state_tid;

//--------------------------------------------------------------------------
// comb delay
    assign state_tid = (NUM_CHANNELS <= 1) ? '0 : i_tid;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            for (int c = 0; c < NUM_CHANNELS; c = c + 1)
                for (int i = 0; i < M; i = i + 1)
                    delay_q_ff[c][i] <= '0;
        end else if (i_din_valid) begin
            delay_q_ff[state_tid][0] <= din_aligned;

            for (int i = 1; i < M; i = i + 1)
                delay_q_ff[state_tid][i] <= delay_q_ff[state_tid][i - 1];
        end
    end

//--------------------------------------------------------------------------
// dout management
    assign dout_next       = din_aligned - delay_q_ff[state_tid][M-1];
    assign dout_valid_next = i_din_valid                             ;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            dout_ff       <= '0  ;
            dout_valid_ff <= 1'b0;
        end else begin
            dout_valid_ff <= dout_valid_next;

            if (i_din_valid)
                dout_ff <= dout_next;
        end
    end

//--------------------------------------------------------------------------
// output ports
    assign o_dout       = dout_ff      ;
    assign o_dout_valid = dout_valid_ff;
//--------------------------------------------------------------------------

endmodule : cic_comb
