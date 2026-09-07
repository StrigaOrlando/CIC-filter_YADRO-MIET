//`timescale 1ns/1ps

module cic_comb #(
    parameter int IN_WIDTH  = 24,
    parameter int OUT_WIDTH = 24,
    parameter int M         = 1
) (
    input  logic                            clk          ,
    input  logic                            rst_n        ,

    input  logic signed [IN_WIDTH  - 1 : 0] i_din        ,
    input  logic                            i_din_valid  ,

    output logic signed [OUT_WIDTH - 1 : 0] o_dout       ,
    output logic                            o_dout_valid
);

    logic signed [OUT_WIDTH - 1 : 0] din_ext           ;

    logic signed [OUT_WIDTH - 1 : 0] delay_q_ff [0:M-1];

    logic signed [OUT_WIDTH - 1 : 0] dout_ff           ;
    logic signed [OUT_WIDTH - 1 : 0] dout_next         ;

    logic                            dout_valid_ff     ;
    logic                            dout_valid_next   ;

//--------------------------------------------------------------------------
// input sign extension
    generate
        if (OUT_WIDTH > IN_WIDTH) begin : gen_sign_extend
            assign din_ext = {{(OUT_WIDTH - IN_WIDTH){i_din[IN_WIDTH - 1]}}, i_din};
        end else begin : gen_no_extend
            assign din_ext = i_din;
        end
    endgenerate

//--------------------------------------------------------------------------
// comb delay
    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            for (int i = 0; i < M; i = i + 1) begin
                delay_q_ff[i] <= '0;
            end
        end else if (i_din_valid) begin
            delay_q_ff[0] <= din_ext;

            for (int i = 1; i < M; i = i + 1) begin
                delay_q_ff[i] <= delay_q_ff[i - 1];
            end
        end
    end

//--------------------------------------------------------------------------
// dout management
    assign dout_next       = din_ext - delay_q_ff[M - 1];
    assign dout_valid_next = i_din_valid;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            dout_ff       <= '0;
            dout_valid_ff <= '0;
        end else begin
            dout_valid_ff <= dout_valid_next;

            if (i_din_valid) begin
                dout_ff <= dout_next;
            end
        end
    end

//--------------------------------------------------------------------------

//--------------------------------------------------------------------------
// output ports
    assign o_dout       = dout_ff;
    assign o_dout_valid = dout_valid_ff;
//--------------------------------------------------------------------------

endmodule : cic_comb
