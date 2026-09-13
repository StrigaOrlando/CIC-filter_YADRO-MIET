module cic_normalize #(
    parameter int DATA_WIDTH = 29,
    parameter int R = 8          ,
    parameter int M = 1          ,
    parameter int N = 3
) (
    input  logic                         clk         ,
    input  logic                         rst_n       ,

    input  logic signed [DATA_WIDTH-1:0] i_din       ,
    input  logic                         i_din_valid ,

    output logic signed [DATA_WIDTH-1:0] o_dout      ,
    output logic                         o_dout_valid
);

    function automatic longint signed calc_gain(
        input int r,
        input int m,
        input int n
    );

        longint signed gain;

        begin
            gain = 1;

            for (int k = 0; k < n; k = k + 1) begin
                gain = gain * (r * m);
            end

            return gain;
        end

    endfunction


    localparam longint signed GAIN = calc_gain(R, M, N);


    // ------------------------------------------------------------
    // normalization
    // ------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            o_dout       <=   '0;
            o_dout_valid <= 1'b0;

        end else begin

            o_dout_valid <= i_din_valid;

            if (i_din_valid) begin

                o_dout <= $signed(i_din) / GAIN;

            end

        end

    end

endmodule