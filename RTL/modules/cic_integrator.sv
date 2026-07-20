`timescale 1ns/1ps

module cic_int #(
    parameter int IN_WIDTH  = 24,
    parameter int ACC_WIDTH = 24
) (
    input logic clk,
    input logic rst,

    input logic signed [IN_WIDTH-1:0] din,
    input logic din_valid,

    output logic signed [ACC_WIDTH-1:0] dout,
    output logic dout_valid
);

    initial begin
        if (ACC_WIDTH < IN_WIDTH) begin
            $error("ACC_WIDTH must be >= IN_WIDTH");
        end
    end

    logic signed [ACC_WIDTH-1:0] din_ext;
    logic signed [ACC_WIDTH-1:0] sum_w;

    generate
        if (ACC_WIDTH > IN_WIDTH) begin : gen_sign_extend
            assign din_ext = {{(ACC_WIDTH - IN_WIDTH){din[IN_WIDTH-1]}}, din};
        end else begin : gen_no_extend
            assign din_ext = din;
        end
    endgenerate

    assign sum_w = dout + din_ext;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dout <= '0;
            dout_valid <= 1'b0;
        end else begin
            dout_valid <= din_valid;
            if (din_valid) begin
                dout <= sum_w;
            end
        end
    end

endmodule
