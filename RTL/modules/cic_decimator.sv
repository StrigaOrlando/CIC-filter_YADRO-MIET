module cic_dec #(
    parameter int DATA_WIDTH   = 24,
    parameter int R            = 4 ,
    parameter int NUM_CHANNELS = 1 ,
    parameter int TID_WIDTH    = (NUM_CHANNELS <= 1) ? 1 : $clog2(NUM_CHANNELS)
) (
    input  logic                             clk          ,
    input  logic                             rst_n        ,

    input  logic signed [DATA_WIDTH - 1 : 0] i_din        ,
    input  logic                             i_din_valid  ,
    input  logic        [TID_WIDTH  - 1 : 0] i_tid        ,

    output logic signed [DATA_WIDTH - 1 : 0] o_dout       ,
    output logic                             o_dout_valid
);

    localparam int CNT_WIDTH = (R <= 1) ? 1 : $clog2(R);

    // Отдельная фаза децимации для каждого TID
    logic [CNT_WIDTH - 1 : 0] cnt_q_ff [0:NUM_CHANNELS-1];
    logic [CNT_WIDTH - 1 : 0] cnt_q_next                 ;

    logic dout_valid_ff  ;
    logic dout_valid_next;

    logic signed [DATA_WIDTH - 1 : 0] dout_ff;

    logic cnt_is_max                   ;
    logic [TID_WIDTH - 1 : 0] state_tid;

//------------------------------------------------------------
// counter
    assign state_tid  = (NUM_CHANNELS <= 1) ? '0 : i_tid;
    assign cnt_is_max = (cnt_q_ff[state_tid] == (R - 1));

    assign cnt_q_next = (i_din_valid & cnt_is_max) ? '0 : cnt_q_ff[state_tid] + 1'b1;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            for (int c = 0; c < NUM_CHANNELS; c = c + 1)
                cnt_q_ff[c] <= '0;
        end else if (i_din_valid) begin
            cnt_q_ff[state_tid] <= cnt_q_next;
        end
    end
//------------------------------------------------------------

//------------------------------------------------------------
// dout management
    assign dout_valid_next = i_din_valid & cnt_is_max;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            dout_valid_ff <= 1'b0;
            dout_ff       <= '0  ;
        end else begin
            dout_valid_ff <= dout_valid_next;

            if (dout_valid_next)
                dout_ff <= i_din;
        end
    end
//------------------------------------------------------------

//------------------------------------------------------------
// output ports
    assign o_dout       = dout_ff      ;
    assign o_dout_valid = dout_valid_ff;
//------------------------------------------------------------

endmodule : cic_dec
