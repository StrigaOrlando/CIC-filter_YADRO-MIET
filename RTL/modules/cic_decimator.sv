//`timescale 1ns/1ps

module cic_dec #(
    parameter int DATA_WIDTH = 24,
    parameter int R          = 4
) (
    input  logic                             clk          ,
    input  logic                             rst_n        ,

    input  logic signed [DATA_WIDTH - 1 : 0] i_din        ,
    input  logic                             i_din_valid  ,

    output logic signed [DATA_WIDTH - 1 : 0] o_dout       ,
    output logic                             o_dout_valid
);

    localparam int CNT_WIDTH = (R <= 1) ? 1 : $clog2(R);

    logic        [ CNT_WIDTH - 1 : 0] cnt_q_ff         ;
    logic        [ CNT_WIDTH - 1 : 0] cnt_q_next       ;

    logic                             dout_valid_ff    ;
    logic                             dout_valid_next  ;

    logic signed [DATA_WIDTH - 1 : 0] dout_ff          ;

    logic                             cnt_is_max       ;

//------------------------------------------------------------
// counter
    assign cnt_is_max = (cnt_q_ff == (R - 1));

    // variant 1
//    always_comb begin
//        cnt_q_next = cnt_q_ff + 1'b1;
//        if (i_din_valid & cnt_is_max) begin
//            cnt_q_next = '0;
//        end
//    end

    // variant 2
    assign cnt_q_next = (i_din_valid & cnt_is_max) ? '0 : cnt_q_ff + 1'b1;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            cnt_q_ff <= '0;
        end else if (i_din_valid) begin
            cnt_q_ff <= cnt_q_next;
//          cnt_q_ff <= (i_din_valid & cnt_is_max) ? '0 : cnt_q_ff + 1'b1; // not bad too
        end
    end
//------------------------------------------------------------

//------------------------------------------------------------
// dout managment
    assign dout_valid_next = i_din_valid & cnt_is_max;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            dout_valid_ff <= '0;
            dout_ff       <= '0;
        end else begin
            dout_valid_ff <= dout_valid_next;

            if (i_din_valid) begin
                dout_ff <= i_din;
            end
        end
    end
//------------------------------------------------------------

//------------------------------------------------------------
// output ports
    assign o_dout       = dout_ff;
    assign o_dout_valid = dout_valid_ff;
//------------------------------------------------------------

endmodule : cic_dec
