function write_info_txt(filename, cfg, info, test_name, input_len, output_len)
% WRITE_INFO_TXT Запись краткой информации о тестовом случае.
%
% Файл info.txt нужен, чтобы потом было понятно:
%   - какой тест запускался;
%   - какие параметры CIC использовались;
%   - какая была полная разрядность;
%   - какая была выходная разрядность;
%   - какая фаза децимации применялась.

    fid = fopen(filename, 'w');

    if fid < 0
        error("Не удалось открыть файл: %s", filename);
    end

    cleanup = onCleanup(@() fclose(fid));

    fprintf(fid, "test_name = %s\n", test_name);
    fprintf(fid, "input_len = %d\n", input_len);
    fprintf(fid, "output_len = %d\n", output_len);
    fprintf(fid, "\n");

    fprintf(fid, "IN_WIDTH = %d\n", cfg.IN_WIDTH);
    fprintf(fid, "OUT_WIDTH = %d\n", cfg.OUT_WIDTH);
    fprintf(fid, "R = %d\n", cfg.R);
    fprintf(fid, "M = %d\n", cfg.M);
    fprintf(fid, "N = %d\n", cfg.N);
    fprintf(fid, "OUTPUT_MODE = %s\n", cfg.OUTPUT_MODE);
    fprintf(fid, "ROUND_MODE = %s\n", cfg.ROUND_MODE);
    fprintf(fid, "NORMALIZE = %d\n", cfg.NORMALIZE);
    fprintf(fid, "\n");

    fprintf(fid, "gain = %d\n", info.gain);
    fprintf(fid, "growth_width = %d\n", info.growth_width);
    fprintf(fid, "full_width = %d\n", info.full_width);
    fprintf(fid, "internal_width = %d\n", info.internal_width);
    fprintf(fid, "output_width = %d\n", info.output_width);
    fprintf(fid, "normalization_shift = %d\n", info.normalization_shift);
    fprintf(fid, "decimation_phase = %d\n", info.decimation_phase);
end