`timescale 1ns/1ps

module cic_comb #(
    parameter int IN_WIDTH = 24,
    parameter int OUT_WIDTH = 24,
    parameter int M = 1
) (
    input logic clk,
    input logic rst,

    input logic signed [IN_WIDTH-1:0] din,
    input logic din_valid,

    output logic signed [OUT_WIDTH-1:0] dout,
    output logic dout_valid
);

    initial begin
        if (OUT_WIDTH < IN_WIDTH) begin
            $error("OUT_WIDTH must be >= IN_WIDTH");
        end

        if (M < 1) begin
            $error("M must be >= 1");
        end
    end

    logic signed [OUT_WIDTH-1:0] din_ext;
    logic signed [OUT_WIDTH-1:0] delay_q [0:M-1];
    logic signed [OUT_WIDTH-1:0] diff_w;

    generate
        if (OUT_WIDTH > IN_WIDTH) begin : gen_sign_extend
            assign din_ext = {{(OUT_WIDTH - IN_WIDTH){din[IN_WIDTH-1]}}, din};
        end else begin : gen_no_extend
            assign din_ext = din;
        end
    endgenerate

    assign diff_w = din_ext - delay_q[M-1];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dout <= '0;
            dout_valid <= 1'b0;

            for (int i = 0; i < M; i = i + 1) begin
                delay_q[i] <= '0;
            end
        end else begin
            dout_valid <= din_valid;

            if (din_valid) begin
                dout <= diff_w;

                delay_q[0] <= din_ext;

                for (int i = 1; i < M; i = i + 1) begin
                    delay_q[i] <= delay_q[i-1];
                end
            end
        end
    end

endmodule