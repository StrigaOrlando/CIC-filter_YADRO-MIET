`timescale 1ns/1ps

module count_bin #(
    parameter int R = 1023
) (
    input logic clk,
    input logic rst,
    input logic enable,

    output logic tick
);

    initial begin
        if (R < 1) begin
            $error("R must be >= 1");
        end
    end

    localparam int CNT_WIDTH = (R <= 1) ? 1 : $clog2(R);

    localparam logic [CNT_WIDTH-1:0] TERM_COUNT = R - 1;

    logic [CNT_WIDTH-1:0] cnt_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt_q <= '0;
            tick <= 1'b0;
        end else begin
            tick <= 1'b0;

            if (enable) begin
                if (cnt_q == TERM_COUNT) begin
                    cnt_q <= '0;
                    tick <= 1'b1;
                end else begin
                    cnt_q <= cnt_q + 1'b1;
                end
            end
        end
    end

endmodule
