function cfg = make_cfg(IN_WIDTH, OUT_WIDTH, R, M, N, OUTPUT_MODE, ROUND_MODE, NORMALIZE)
% MAKE_CFG Создание структуры параметров CIC-фильтра.
%
% Эта функция нужна, чтобы удобно задавать разные наборы параметров
% для автоматического прогона тестов.

    cfg.IN_WIDTH = IN_WIDTH;
    cfg.OUT_WIDTH = OUT_WIDTH;

    cfg.R = R;
    cfg.M = M;
    cfg.N = N;

    cfg.OUTPUT_MODE = string(OUTPUT_MODE);
    cfg.ROUND_MODE = string(ROUND_MODE);
    cfg.NORMALIZE = logical(NORMALIZE);
end