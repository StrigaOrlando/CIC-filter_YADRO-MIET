module cic_int #(
    parameter int IN_WIDTH     = 24,
    parameter int ACC_WIDTH    = 24,
    parameter int IN_SCALE     = 0 ,
    parameter int ACC_SCALE    = 0 ,
    parameter int NUM_CHANNELS = 1 ,
    parameter int TID_WIDTH    = (NUM_CHANNELS <= 1) ? 1 : $clog2(NUM_CHANNELS)
) (
    input  logic                            clk          ,
    input  logic                            rst_n        ,

    input  logic signed [IN_WIDTH  - 1 : 0] i_din        ,
    input  logic                            i_din_valid  ,
    input  logic        [TID_WIDTH - 1 : 0] i_tid        ,

    output logic signed [ACC_WIDTH - 1 : 0] o_dout       ,
    output logic                            o_dout_valid
);
    localparam int LEFT_SHIFT  = (IN_SCALE > ACC_SCALE) ? (IN_SCALE-ACC_SCALE) : 0                      ;
    localparam int ALIGN_WIDTH = ((IN_WIDTH+LEFT_SHIFT) > ACC_WIDTH) ? (IN_WIDTH+LEFT_SHIFT) : ACC_WIDTH;
    logic signed [ALIGN_WIDTH-1:0] input_wide                                                           ;
    logic signed [ALIGN_WIDTH-1:0] aligned_wide                                                         ;
    logic signed [ACC_WIDTH-1:0] din_ext                                                                ;

    assign input_wide = $signed(i_din);
    generate
        if (IN_SCALE > ACC_SCALE) begin : gen_scale_left
            assign aligned_wide = input_wide <<< (IN_SCALE - ACC_SCALE);
        end else if (IN_SCALE < ACC_SCALE) begin : gen_scale_right
            assign aligned_wide = input_wide >>> (ACC_SCALE - IN_SCALE);
        end else begin : gen_scale_same
            assign aligned_wide = input_wide;
        end
    endgenerate
    assign din_ext = aligned_wide       ;
    logic [TID_WIDTH - 1 : 0] state_tid ;

    // Отдельное состояние интегратора для каждого TID
    logic signed [ACC_WIDTH - 1 : 0] acc_q_ff [0:NUM_CHANNELS-1];
    logic signed [ACC_WIDTH - 1 : 0] acc_q_next                 ;

    logic [TID_WIDTH - 1 : 0] dout_tid_ff;
    logic dout_valid_ff                  ;
    logic dout_valid_next                ;

//--------------------------------------------------------------------------
// integrator
    assign state_tid  = (NUM_CHANNELS <= 1) ? '0 : i_tid;
    assign acc_q_next = acc_q_ff[state_tid] + din_ext   ;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            for (int c = 0; c < NUM_CHANNELS; c = c + 1)
                acc_q_ff[c] <= '0;
        end else if (i_din_valid) begin
            acc_q_ff[state_tid] <= acc_q_next;
        end
    end

//--------------------------------------------------------------------------
// dout valid management
    assign dout_valid_next = i_din_valid;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            dout_valid_ff <= 1'b0;
            dout_tid_ff   <= '0  ;
        end else begin
            dout_valid_ff <= dout_valid_next;

            if (i_din_valid)
                dout_tid_ff <= state_tid;
        end
    end

//--------------------------------------------------------------------------
// output ports
    assign o_dout       = acc_q_ff[dout_tid_ff];
    assign o_dout_valid = dout_valid_ff        ;
//--------------------------------------------------------------------------

endmodule : cic_int
