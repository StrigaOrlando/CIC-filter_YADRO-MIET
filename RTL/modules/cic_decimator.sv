`timescale 1ns/1ps

module cic_dec #(
    parameter int DATA_WIDTH = 24,
    parameter int R = 4
) (
    input logic clk,
    input logic rst,

    input logic signed [DATA_WIDTH-1:0] din,
    input logic din_valid,

    output logic signed [DATA_WIDTH-1:0] dout,
    output logic dout_valid
);

    initial begin
        if (R < 1) begin
            $error("R must be >= 1");
        end
    end

    localparam int CNT_WIDTH = (R <= 1) ? 1 : $clog2(R);

    logic [CNT_WIDTH-1:0] cnt_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt_q <= '0;
            dout <= '0;
            dout_valid <= 1'b0;
        end else begin
            dout_valid <= 1'b0;

            if (din_valid) begin
                if (cnt_q == R - 1) begin
                    dout <= din;
                    dout_valid <= 1'b1;
                    cnt_q <= '0;
                end else begin
                    cnt_q <= cnt_q + 1'b1;
                end
            end
        end
    end

endmodule