//`timescale 1ns/1ps

module cic_int #(
    parameter int IN_WIDTH  = 24,
    parameter int ACC_WIDTH = 24
) (
    input  logic                            clk          ,
    input  logic                            rst_n        ,

    input  logic signed [IN_WIDTH  - 1 : 0] i_din        ,
    input  logic                            i_din_valid  ,

    output logic signed [ACC_WIDTH - 1 : 0] o_dout       ,
    output logic                            o_dout_valid
);

    logic signed [ACC_WIDTH - 1 : 0] din_ext        ;

    logic signed [ACC_WIDTH - 1 : 0] acc_q_ff       ;
    logic signed [ACC_WIDTH - 1 : 0] acc_q_next     ;

    logic                            dout_valid_ff  ;
    logic                            dout_valid_next;

//--------------------------------------------------------------------------
// input sign extension
    generate
        if (ACC_WIDTH > IN_WIDTH) begin : gen_sign_extend
            assign din_ext = {{(ACC_WIDTH - IN_WIDTH){i_din[IN_WIDTH - 1]}}, i_din};
        end else begin : gen_no_extend
            assign din_ext = i_din;
        end
    endgenerate

//--------------------------------------------------------------------------
// integrator
    assign acc_q_next = acc_q_ff + din_ext;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            acc_q_ff <= '0;
        end else if (i_din_valid) begin
            acc_q_ff <= acc_q_next;
        end
    end

//--------------------------------------------------------------------------
// dout valid management
    assign dout_valid_next = i_din_valid;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            dout_valid_ff <= '0;
        end else begin
            dout_valid_ff <= dout_valid_next;
        end
    end

//--------------------------------------------------------------------------

//--------------------------------------------------------------------------
// output ports
    assign o_dout       = acc_q_ff;
    assign o_dout_valid = dout_valid_ff;
//--------------------------------------------------------------------------

endmodule : cic_int
