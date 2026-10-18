//`timescale 1ns/1ps

module cic_fir_comp #(
    parameter int IN_WIDTH        = 16,
    parameter int OUT_WIDTH       = 24,
    parameter int L               = 7,
    parameter int COEFF_FRAC_BITS = 7,
    parameter int signed COEFF_Q [0:3] = '{256, -64, 1, 4}
) (
    input  logic                             clk,
    input  logic                             rst_n,

    input  logic signed [IN_WIDTH  - 1 : 0] i_din,
    input  logic                             i_din_valid,

    output logic signed [OUT_WIDTH - 1 : 0] o_dout,
    output logic                             o_dout_valid
);

    localparam int HALF_TAPS = (L - 1) / 2;   // Количество пар симметричных отсчётов
    localparam int N_TERMS   = HALF_TAPS + 1; // Количество независимых коэффициентов
    localparam int SYM_WIDTH = IN_WIDTH + 1;  // Разрядность суммы пары отсчётов

// Максимальный сдвиг среди коэффициентов
    function automatic int calc_max_coeff_shift;
        int abs_coeff;
        begin
            calc_max_coeff_shift = 0;

            for (int i = 0; i <= HALF_TAPS; i = i + 1) begin
                abs_coeff = (COEFF_Q[i] < 0) ? -COEFF_Q[i] : COEFF_Q[i];

                if ((abs_coeff > 1) && ($clog2(abs_coeff) > calc_max_coeff_shift))
                    calc_max_coeff_shift = $clog2(abs_coeff);
            end
        end
    endfunction

    localparam int MAX_COEFF_SHIFT = calc_max_coeff_shift();
    localparam int ACC_WIDTH = SYM_WIDTH + MAX_COEFF_SHIFT + $clog2(N_TERMS) + 1; // Внутренняя разрядность КИХ

    logic signed [IN_WIDTH  - 1 : 0] delay_q_ff [0:L-2];
    logic signed [IN_WIDTH  - 1 : 0] fir_window [0:L-1];
    logic signed [SYM_WIDTH - 1 : 0] sym_data [0:HALF_TAPS];
    logic signed [ACC_WIDTH - 1 : 0] coeff_term [0:HALF_TAPS];
    logic signed [ACC_WIDTH - 1 : 0] sum_stage [0:HALF_TAPS];
    logic signed [ACC_WIDTH - 1 : 0] scaled_sum;
    logic signed [OUT_WIDTH - 1 : 0] resized_sum;

// Линия задержки входных отсчётов
    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            for (int i = 0; i < L - 1; i = i + 1)
                delay_q_ff[i] <= '0;
        end
        else if (i_din_valid) begin
            delay_q_ff[0] <= i_din;

            for (int i = 1; i < L - 1; i = i + 1)
                delay_q_ff[i] <= delay_q_ff[i - 1];
        end
    end

// Окно отсчётов КИХ
    assign fir_window[0] = i_din;

    generate
        for (genvar i = 1; i < L; i = i + 1) begin : gen_fir_window
            assign fir_window[i] = delay_q_ff[i - 1];
        end
    endgenerate

// Сложение отсчётов в симметричных позициях окна
// Наример, для L = 5:
// h = [c2 c1 c0 c1 c2]
// y = c0*x[n-2] + c1*(x[n-1] + x[n-3]) + c2*(x[n] + x[n-4])
    assign sym_data[0] = fir_window[HALF_TAPS];

    generate
        for (genvar j = 1; j <= HALF_TAPS; j = j + 1) begin : gen_symmetry
            assign sym_data[j] =
                $signed({fir_window[HALF_TAPS-j][IN_WIDTH-1], fir_window[HALF_TAPS-j]}) +
                $signed({fir_window[HALF_TAPS+j][IN_WIDTH-1], fir_window[HALF_TAPS+j]});
        end
    endgenerate

// Умножение на коэффициенты вида 0 или +/-2^k
    generate
        for (genvar k = 0; k <= HALF_TAPS; k = k + 1) begin : gen_coeff
            localparam int signed COEFF_VALUE = COEFF_Q[k];
            localparam int ABS_COEFF = (COEFF_VALUE < 0) ? -COEFF_VALUE : COEFF_VALUE;
            localparam int COEFF_SHIFT = (ABS_COEFF <= 1) ? 0 : $clog2(ABS_COEFF);

            logic signed [ACC_WIDTH - 1 : 0] sym_data_ext;

            assign sym_data_ext = {{(ACC_WIDTH-SYM_WIDTH){sym_data[k][SYM_WIDTH-1]}}, sym_data[k]};

            if (COEFF_VALUE == 0)
                assign coeff_term[k] = '0;
            else if (COEFF_VALUE < 0)
                assign coeff_term[k] = -(sym_data_ext <<< COEFF_SHIFT);
            else
                assign coeff_term[k] =  (sym_data_ext <<< COEFF_SHIFT);
        end
    endgenerate

// Итоговое суммирование слагаемых КИХ
    assign sum_stage[0] = coeff_term[0];

    generate
        for (genvar m = 1; m <= HALF_TAPS; m = m + 1) begin : gen_sum
            assign sum_stage[m] = sum_stage[m - 1] + coeff_term[m];
        end
    endgenerate

// Удаление добавленного масштаба коэффициентов
    assign scaled_sum = $signed(sum_stage[HALF_TAPS]) >>> COEFF_FRAC_BITS;

// Приведение к выходгой разрядности
// при уменьшении удаляются добавленные старшие биты, если не хватает, wrap-around, при увеличении знаковое расширение
    assign resized_sum = $signed(scaled_sum);

// Запись выхода
    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            o_dout       <= '0;
            o_dout_valid <= 1'b0;
        end
        else begin
            o_dout_valid <= i_din_valid;

            if (i_din_valid)
                o_dout <= resized_sum;
        end
    end

endmodule : cic_fir_comp
