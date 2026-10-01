// ============================================================================
// В данном файле package есть 
// Hogenauer accumulator pruning technique
// --------------- ПАРАМЕТРЫ: ---------------
// Ширина входных данных, ширина выходных данных [20:10],
// количество стадий CIC фильтра, коэффициент децимации, задержка comb-секции,
// ---------------- РЕЖИМЫ: -----------------
// Выходной разрядности, округления, нормировки,
// Hogenauer pruning, компенсации АЧХ, расширения полосы задерживания
// ============================================================================

package cic_parameters_pkg;

    localparam IN_WIDTH      = 12;
    localparam OUT_WIDTH     = 12;
    localparam N             = 3; // Количество стадий CIC фильтра (от 2 до 6)
    localparam M             = 1; // Задержка comb-секции (1 или 2)
    localparam R             = 8; // Коэффициент децимации R ≤ 700

    localparam bit OUTPUT_MODE        = 1'b0; // Полная/неполная выходная разрядность 1/0
    localparam bit NORMALIZE          = 1'b0; // Наличие/отсутствие нормировки 1/0
    localparam bit PRUNING_EN         = 1'b0; // наличие/отсутствие Hogenauer pruning 1/0
    localparam bit STOPBAND_EXT       = 1'b0; // наличие/отсутствие расширения полосы задерживания 1/0

    localparam logic [1:0] ROUND_MODE = 2'd0; // режимы округления для приведения разрядности, 0 - усечение, 1 - к +inf, 2 - к нулю
    localparam bit COMP_AFR           = 1'b0; // ????????

    localparam int STAGES       = 7;
    localparam int BITS_GROWTH  = 9;
    localparam int FULL_WIDTH   = 21;
    localparam int TRUNC_BITS   = 9;

    // -----------------------------------------------------------
    //   Bj[j]          - количество бит усекаемых на каждом каскаде j
    //   AccumWidth[j]  - оставшееся кол-во бит на каскаде j
    // -----------------------------------------------------------
    localparam int Bj         [1:7] = '{0, 3, 4, 5, 6, 7, 9};
    localparam int AccumWidth [1:7] = '{21, 18, 17, 16, 15, 14, 12};


endpackage
