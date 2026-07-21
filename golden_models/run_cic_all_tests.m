clear; clc; close all;

% ============================================================
% Набор тестов для CIC golden model
%
% Проверяются воздействия из ТЗ:
%   1. нулевой вход
%   2. постоянный вход
%   3. одиночный импульс
%   4. ступенька
%   5. синус в полосе пропускания
%   6. синус около первой зоны подавления
%   7. псевдослучайный signed-сигнал
%   8. максимальные положительные и отрицательные значения
%   9. несколько наборов параметров R, N, M
%
% Для каждого теста формируются:
%   input.txt
%   expected_output.txt
% ============================================================

out_dir = "cic_test_vectors";

if ~exist(out_dir, "dir")
    mkdir(out_dir);
end

% -------------------------
% Наборы параметров фильтра
% -------------------------
cfg_list = {};

cfg_list{end+1} = make_cfg(16, 16, 4,  1, 2, "full",   "trunc", false);
cfg_list{end+1} = make_cfg(16, 16, 8,  1, 3, "custom", "trunc", false);
cfg_list{end+1} = make_cfg(16, 16, 16, 1, 4, "custom", "ceil",  false);
cfg_list{end+1} = make_cfg(16, 16, 32, 1, 5, "custom", "fix",   false);
cfg_list{end+1} = make_cfg(12, 12, 8,  2, 3, "custom", "trunc", false);

% Нормировку пока проверяем только для случая, где gain является степенью двойки.
cfg_list{end+1} = make_cfg(16, 16, 4,  1, 2, "custom", "trunc", true);

% Количество входных отсчётов.
% Лучше брать кратным R, чтобы длина выхода была предсказуемой.
num_samples_base = 1024;

total_tests = 0;
passed_tests = 0;

for cfg_idx = 1:length(cfg_list)

    cfg = cfg_list{cfg_idx};

    % Длину входа делаем кратной R
    num_samples = ceil(num_samples_base / cfg.R) * cfg.R;

    % -------------------------
    % Генерация воздействий
    % -------------------------
    tests = make_test_inputs(cfg, num_samples);

    for test_idx = 1:length(tests)

        test_name = tests{test_idx}.name;
        x = tests{test_idx}.x;

        total_tests = total_tests + 1;

        try
            [y, info] = cic_golden_fixed(x, cfg);

            % Проверка базовой корректности результата
            check_result(x, y, info, cfg, test_name);

            % Имя папки для конкретного теста
            case_name = sprintf( ...
                "cfg%02d_R%d_M%d_N%d_IN%d_OUT%d_%s_%s_norm%d_%s", ...
                cfg_idx, cfg.R, cfg.M, cfg.N, cfg.IN_WIDTH, cfg.OUT_WIDTH, ...
                cfg.OUTPUT_MODE, cfg.ROUND_MODE, cfg.NORMALIZE, test_name);

            case_dir = fullfile(out_dir, case_name);

            if ~exist(case_dir, "dir")
                mkdir(case_dir);
            end

            % Запись входных и эталонных выходных данных
            write_vector_txt(fullfile(case_dir, "input.txt"), x);
            write_vector_txt(fullfile(case_dir, "expected_output.txt"), y);

            % Дополнительно сохраняем промежуточные данные для отладки
            write_vector_txt(fullfile(case_dir, "after_integrators.txt"), info.after_integrators);
            write_vector_txt(fullfile(case_dir, "after_decimator.txt"), info.after_decimator);
            write_vector_txt(fullfile(case_dir, "after_combs.txt"), info.after_combs);

            % Сохраняем краткую информацию по тесту
            write_info_txt(fullfile(case_dir, "info.txt"), cfg, info, test_name, length(x), length(y));

            fprintf("[OK] cfg=%02d, test=%s, y_len=%d, full_width=%d, out_width=%d\n", ...
                cfg_idx, test_name, length(y), info.full_width, info.output_width);

            passed_tests = passed_tests + 1;

        catch ME
            fprintf("[FAIL] cfg=%02d, test=%s\n", cfg_idx, test_name);
            fprintf("       %s\n", ME.message);
        end
    end
end

fprintf("\nИтого: %d / %d тестов успешно.\n", passed_tests, total_tests);

if passed_tests ~= total_tests
    error("Часть тестов завершилась с ошибкой.");
end

disp("Все тесты golden model завершены успешно.");