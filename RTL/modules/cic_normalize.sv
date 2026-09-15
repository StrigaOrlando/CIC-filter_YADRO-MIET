module cic_normalize #(
    parameter int DATA_WIDTH = 29        ,
    parameter longint unsigned GAIN = 512
) (
    input  logic                         clk         ,
    input  logic                         rst_n       ,

    input  logic signed [DATA_WIDTH-1:0] i_din,
    input  logic                         i_din_valid ,

    output logic signed [DATA_WIDTH-1:0] o_dout      ,
    output logic                         o_dout_valid
);

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            o_dout       <= '0  ;
            o_dout_valid <= 1'b0;

        end else begin

            o_dout_valid <= i_din_valid;

            if (i_din_valid)
                o_dout <= $signed(i_din) / $signed(GAIN);

        end

    end

endmodule
