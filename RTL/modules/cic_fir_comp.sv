//`timescale 1ns/1ps

module cic_fir_comp #(
    parameter int IN_WIDTH        = 16,
    parameter int OUT_WIDTH       = 24,
    parameter int L               = 7 ,
    parameter int COEFF_FRAC_BITS = 7 ,
    parameter int signed COEFF_Q [0:3] = '{256, -64, 1, 4}
) (
    input  logic                            clk          ,
    input  logic                            rst_n        ,

    input  logic signed [IN_WIDTH  - 1 : 0] i_din        ,
    input  logic                            i_din_valid  ,

    output logic signed [OUT_WIDTH - 1 : 0] o_dout       ,
    output logic                            o_dout_valid
);

    localparam int HALF_TAPS = (L - 1) / 2  ; // Количество пар симметричных отсчётов
    localparam int N_TERMS   = HALF_TAPS + 1; // Количество независимых коэффициентов
    localparam int SYM_WIDTH = IN_WIDTH + 1 ; // Разрядность суммы пары отсчётов

// Максимальный сдвиг для коэффициентов
    function automatic int calc_max_coeff_shift;
        int i        ;
        int abs_coeff;
        int shift    ;

        begin
            calc_max_coeff_shift = 0;

            for (i = 0; i <= HALF_TAPS; i = i + 1) begin
                abs_coeff = (COEFF_Q[i] < 0) ? -COEFF_Q[i] : COEFF_Q[i];
                shift     = (abs_coeff <= 1) ? 0 : $clog2(abs_coeff)   ;

                if (shift > calc_max_coeff_shift) begin
                    calc_max_coeff_shift = shift;
                end
            end
        end
    endfunction

    localparam int MAX_COEFF_SHIFT = calc_max_coeff_shift(); // Максимальный сдвиг среди коэффициентов

    localparam int ACC_WIDTH = SYM_WIDTH + MAX_COEFF_SHIFT + $clog2(N_TERMS) + 1; // Разрядность сумматора КИХ

    logic signed [IN_WIDTH - 1 : 0] delay_q_ff [0:L-2]        ;
    logic signed [IN_WIDTH - 1 : 0] fir_window [0:L-1]        ;

    logic signed [SYM_WIDTH - 1 : 0] sym_data [0:HALF_TAPS]   ;

    logic signed [ACC_WIDTH - 1 : 0] coeff_term [0:HALF_TAPS] ;
    logic signed [ACC_WIDTH - 1 : 0] sum_stage [0:HALF_TAPS]  ;

    logic signed [ACC_WIDTH - 1 : 0] scaled_sum               ;
    logic signed [OUT_WIDTH - 1 : 0] resized_sum              ;

    logic signed [OUT_WIDTH - 1 : 0] dout_ff                  ;
    logic signed [OUT_WIDTH - 1 : 0] dout_next                ;

    logic                            dout_valid_ff            ;
    logic                            dout_valid_next          ;

// Линия задержки входных отсчётов
    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            for (int i = 0; i < L - 1; i = i + 1) begin
                delay_q_ff[i] <= '0;
            end
        end else if (i_din_valid) begin
            delay_q_ff[0] <= i_din;

            for (int i = 1; i < L - 1; i = i + 1) begin
                delay_q_ff[i] <= delay_q_ff[i - 1];
            end
        end
    end

// Окно отсчётов КИХ-фильтра
    assign fir_window[0] = i_din;

    generate
        genvar i;
        for (i = 1; i < L; i = i + 1) begin : gen_fir_window
            assign fir_window[i] = delay_q_ff[i - 1];
        end
    endgenerate

// Предварительное сложение симметричных отсчётов
//
// Например, для L = 5:
// h = [c2 c1 c0 c1 c2]
// y = c0*x[n-2] + c1*(x[n-1] + x[n-3]) + c2*(x[n] + x[n-4])
    assign sym_data[0] = {fir_window[HALF_TAPS][IN_WIDTH - 1], fir_window[HALF_TAPS]};

    generate
        genvar j;
        for (j = 1; j <= HALF_TAPS; j = j + 1) begin : gen_symmetry
            logic signed [SYM_WIDTH - 1 : 0] data_a_ext;
            logic signed [SYM_WIDTH - 1 : 0] data_b_ext;

            assign data_a_ext = {fir_window[HALF_TAPS - j][IN_WIDTH - 1], fir_window[HALF_TAPS - j]};

            assign data_b_ext = {fir_window[HALF_TAPS + j][IN_WIDTH - 1], fir_window[HALF_TAPS + j]};

            assign sym_data[j] = data_a_ext + data_b_ext;
        end
    endgenerate

// Умножение на коэффициенты
    generate
        genvar k;
        for (k = 0; k <= HALF_TAPS; k = k + 1) begin : gen_coeff
            localparam int signed COEFF_VALUE = COEFF_Q[k];
            localparam int ABS_COEFF = (COEFF_VALUE < 0) ? -COEFF_VALUE : COEFF_VALUE;
            localparam int COEFF_SHIFT = (ABS_COEFF <= 1) ? 0 : $clog2(ABS_COEFF);

            logic signed [ACC_WIDTH - 1 : 0] sym_data_ext;

            assign sym_data_ext = {{(ACC_WIDTH - SYM_WIDTH){sym_data[k][SYM_WIDTH - 1]}}, sym_data[k]};

            if (COEFF_VALUE == 0) begin : gen_zero_coeff
                assign coeff_term[k] = '0;
            end else if (COEFF_VALUE < 0) begin : gen_negative_coeff
                assign coeff_term[k] = -(sym_data_ext <<< COEFF_SHIFT);
            end else begin : gen_positive_coeff
                assign coeff_term[k] = sym_data_ext <<< COEFF_SHIFT;
            end
        end
    endgenerate

// Итоговое сложение
    assign sum_stage[0] = coeff_term[0];

    generate
        genvar m;
        for (m = 1; m <= HALF_TAPS; m = m + 1) begin : gen_sum
            assign sum_stage[m] = sum_stage[m - 1] + coeff_term[m];
        end
    endgenerate

// Компенсация масштаба коэффициентов
    assign scaled_sum = $signed(sum_stage[HALF_TAPS]) >>> COEFF_FRAC_BITS;

// Выходная ширина после КИХ-компенсации
    generate
        if (OUT_WIDTH < ACC_WIDTH) begin : gen_out_narrow
            assign resized_sum = scaled_sum[OUT_WIDTH - 1 : 0];
        end else if (OUT_WIDTH > ACC_WIDTH) begin : gen_out_wide
            assign resized_sum = {{(OUT_WIDTH - ACC_WIDTH){scaled_sum[ACC_WIDTH - 1]}}, scaled_sum};
        end else begin : gen_out_equal
            assign resized_sum = scaled_sum;
        end
    endgenerate

    assign dout_next       = resized_sum;
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

// Выходные сигналы
    assign o_dout       = dout_ff      ;
    assign o_dout_valid = dout_valid_ff;

endmodule : cic_fir_comp