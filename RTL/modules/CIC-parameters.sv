//===========================================
// В данном файле package есть 
// --------------- ПАРАМЕТРЫ: ---------------
// Ширина входных данных, ширина выходных данных [20:10],
// количество стадий CIC фильтра, коэффициент децимации, задержка comb-секции,
// ---------------- РЕЖИМЫ: -----------------
// Выходной разрядности, округления, нормировки,
// Hogenauer pruning, компенсации АЧХ, расширения полосы задерживания
// ---------------- ФУНКЦИИ: ----------------
// Коэффициент усиления CIC, прирост разрядности,
// полная внутренняя/выходная разрядность, 
// количество бит, отбрасываемых при неполной выходной разрядности
//=========================================

package CIC_parameters;

    localparam IN_WIDTH = 10;
    localparam OUT_WIDTH = 10;
    localparam N = 1; // Количество стадий CIC фильтра (от 2 до 6)
    localparam M = 1; // Задержка comb-секции (1 или 2)
    localparam R = 1; // Коэффициент децимации R ≤ 700
    
    localparam bit FULL_OUT_WIDTH = 1'b0; // Полная/неполная выходная разрядность 1/0
    localparam bit NORM_EN        = 1'b0; // Наличие/отсутствие нормировки 1/0
    localparam bit PRUNING_EN     = 1'b0; // наличие/отсутствие Hogenauer pruning 1/0
    localparam bit STOPBAND_EXT   = 1'b0; // наличие/отсутствие расширения полосы задерживания 1/0
    
    localparam bit ROUNDE_MODE    = 1'b0; // ????????
    localparam bit COMP_AFR       = 1'b0; // ????????
    
    localparam GAIN = calc_cic_gain(N, R, M);
    localparam FULL_WIDTH = calc_full_width(IN_WIDTH, N, R, M);
    
    // Расчет коэффициента усиления CIC - GAIN
    function automatic longint unsigned calc_cic_gain(
        input int n_stages, 
        input int dec_ratio, 
        input int diff_delay
    );
        return (dec_ratio * diff_delay) ** n_stages;
    endfunction
    
    // Расчёт прироста разрядности (B_growth)
    function automatic int calc_bit_growth(
        input int n_stages, 
        input int dec_ratio, 
        input int diff_delay
    );
        longint unsigned gain;
        gain = calc_cic_gain(n_stages, dec_ratio, diff_delay);
        return $clog2(gain);
    endfunction

    // Расчёт полной внутренней/выходной разрядности - W_FULL
    function automatic int calc_full_width(
        input int in_width, 
        input int n_stages, 
        input int dec_ratio, 
        input int diff_delay
    );
        return in_width + calc_bit_growth(n_stages, dec_ratio, diff_delay);
    endfunction

    // Расчёт количества отбрасываемых бит при неполной выходной разрядности 
    function automatic int calc_discarded_bits(
        input int full_width, 
        input int out_width, 
        input bit full_out_width // Режим полной входной разрядности
    );
        if (full_out_width)
            return 0; // Ничего не отбрасываем
        else
            return full_width - out_width;
    endfunction
    
endpackage