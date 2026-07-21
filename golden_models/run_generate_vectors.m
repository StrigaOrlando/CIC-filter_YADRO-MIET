clear; clc; close all;

% ============================================================
% Генерация входных и эталонных выходных данных для RTL testbench
%
% Основной сценарий:
%   1. Настроить cfg.
%   2. Выбрать входное воздействие x.
%   3. Запустить этот файл.
%   4. Передать rtl_test_case/input.txt в RTL.
%   5. Сравнивать RTL-выход с rtl_test_case/expected_output.txt.
% ============================================================

out_dir = "rtl_test_case";

if ~exist(out_dir, "dir")
    mkdir(out_dir);
end

% ============================================================
% 1. Конфигурация CIC-фильтра
% ============================================================
% make_cfg(IN_WIDTH, OUT_WIDTH, R, M, N, OUTPUT_MODE, ROUND_MODE, NORMALIZE)
%
% OUTPUT_MODE:
%   "full"   - полная расчётная выходная разрядность;
%   "custom" - выходная разрядность задаётся OUT_WIDTH.
%
% ROUND_MODE используется только при OUTPUT_MODE = "custom":
%   "trunc" - усечение;
%   "ceil"  - округление в +inf;
%   "fix"   - округление к нулю.
%
% NORMALIZE:
%   false - нормировка выключена;
%   true  - нормировка включена, пока только для gain = 2^k.

cfg = make_cfg(16, 16, 4, 1, 2, "full", "trunc", false);

% ============================================================
% 2. Фаза децимации
% ============================================================
% По умолчанию golden model использует DECIMATION_PHASE = R.
% Это значит: первый выходной отсчёт формируется на R-м входном отсчёте.
%
% Для RTL нужно использовать такую же фазу.
%
% Обычно это поле можно не задавать, тогда будет cfg.R.
% Оставлено явно для понятности.
cfg.DECIMATION_PHASE = cfg.R;

% ============================================================
% 3. Графики
% ============================================================
% Для генерации векторов графики обычно выключены.
% Чтобы посмотреть сигналы, лучше использовать run_cic_plot_example.m.

cfg.PLOT_ENABLE = false;

% ============================================================
% 4. Выбор входного воздействия
% ============================================================
% Важно: num_samples лучше делать кратным R,
% чтобы длина выхода была равна num_samples / R.

num_samples = 128;
num_samples = ceil(num_samples / cfg.R) * cfg.R;

in_min = -2^(cfg.IN_WIDTH - 1);
in_max =  2^(cfg.IN_WIDTH - 1) - 1;

% ------------------------------------------------------------
% Вариант 1: постоянный вход
% ------------------------------------------------------------
x = 100 * ones(num_samples, 1);

% ------------------------------------------------------------
% Вариант 2: одиночный импульс
% ------------------------------------------------------------
% x = zeros(num_samples, 1);
% x(1) = 100;

% ------------------------------------------------------------
% Вариант 3: ступенька
% ------------------------------------------------------------
% x = zeros(num_samples, 1);
% x(floor(num_samples/4):end) = 100;

% ------------------------------------------------------------
% Вариант 4: синус в полосе пропускания
% ------------------------------------------------------------
% n = (0:num_samples-1).';
% amp = round(0.25 * in_max);
% f_pass = 1 / (16 * cfg.R);
% x = round(amp * sin(2*pi*f_pass*n));

% ------------------------------------------------------------
% Вариант 5: синус около первой зоны подавления
% ------------------------------------------------------------
% n = (0:num_samples-1).';
% amp = round(0.25 * in_max);
% f_stop = 1 / (cfg.R * cfg.M);
% f_near_stop = 0.95 * f_stop;
% x = round(amp * sin(2*pi*f_near_stop*n));

% ------------------------------------------------------------
% Вариант 6: псевдослучайный signed-сигнал
% ------------------------------------------------------------
% rng(1);
% x = randi([in_min, in_max], num_samples, 1);

% ------------------------------------------------------------
% Вариант 7: максимальные положительные и отрицательные значения
% ------------------------------------------------------------
% x = zeros(num_samples, 1);
% x(1:2:end) = in_max;
% x(2:2:end) = in_min;

% ============================================================
% 5. Запуск golden model
% ============================================================

[y, info] = cic_golden_fixed(x, cfg);

% ============================================================
% 6. Запись файлов для RTL
% ============================================================

write_vector_txt(fullfile(out_dir, "input.txt"), x);
write_vector_txt(fullfile(out_dir, "expected_output.txt"), y);

% Промежуточные сигналы полезны для отладки RTL,
% если итоговый выход не совпал.
write_vector_txt(fullfile(out_dir, "after_integrators.txt"), info.after_integrators);
write_vector_txt(fullfile(out_dir, "after_decimator.txt"), info.after_decimator);
write_vector_txt(fullfile(out_dir, "after_combs.txt"), info.after_combs);

write_info_txt(fullfile(out_dir, "info.txt"), cfg, info, "single_case", length(x), length(y));

% ============================================================
% 7. Краткий вывод
% ============================================================

fprintf("Тестовые векторы успешно сформированы.\n");
fprintf("Папка: %s\n", out_dir);
fprintf("input.txt             - вход для RTL\n");
fprintf("expected_output.txt   - эталонный выход MATLAB\n");
fprintf("info.txt              - параметры теста\n");
fprintf("\n");

fprintf("Параметры:\n");
fprintf("IN_WIDTH = %d\n", cfg.IN_WIDTH);
fprintf("OUT_WIDTH = %d\n", cfg.OUT_WIDTH);
fprintf("R = %d\n", cfg.R);
fprintf("M = %d\n", cfg.M);
fprintf("N = %d\n", cfg.N);
fprintf("OUTPUT_MODE = %s\n", cfg.OUTPUT_MODE);
fprintf("ROUND_MODE = %s\n", cfg.ROUND_MODE);
fprintf("NORMALIZE = %d\n", cfg.NORMALIZE);
fprintf("DECIMATION_PHASE = %d\n", info.decimation_phase);
fprintf("gain = %d\n", info.gain);
fprintf("full_width = %d\n", info.full_width);
fprintf("output_width = %d\n", info.output_width);
fprintf("input length = %d\n", length(x));
fprintf("output length = %d\n", length(y));