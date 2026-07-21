clear; clc; close all;

% ============================================================
% Пример запуска CIC golden model с графиками
%
% Этот скрипт нужен только для визуальной отладки.
% Для массовых тестов run_cic_all_tests графики лучше не включать.
% ============================================================

% -------------------------
% Конфигурация CIC-фильтра
% -------------------------
cfg = make_cfg(16, 16, 4, 1, 2, "full", "trunc", false);

% -------------------------
% Включение/отключение графиков
% -------------------------
% true  - графики будут построены;
% false - графики не будут построены.
cfg.PLOT_ENABLE = true;

% true  - показать вход, сигнал после интеграторов,
%         сигнал после децимации, сигнал после comb и итоговый выход;
% false - показать только вход и итоговый выход.
cfg.PLOT_INTERNAL = true;

% Сколько отсчётов максимум показывать на графиках.
% Если сигнал длиннее, будут показаны только первые PLOT_MAX_SAMPLES отсчётов.
cfg.PLOT_MAX_SAMPLES = 100;

% -------------------------
% Выбор входного воздействия
% -------------------------
num_samples = 128;

% Вариант 1: постоянный вход
%x = 100 * ones(num_samples, 1);

% Вариант 2: одиночный импульс
% x = zeros(num_samples, 1);
% x(1) = 100;

% Вариант 3: ступенька
% x = zeros(num_samples, 1);
% x(floor(num_samples/4):end) = 100;

% Вариант 4: синус в полосе пропускания
% n = (0:num_samples-1).';
% amp = 1000;
% f_pass = 1 / (16 * cfg.R);
% x = round(amp * sin(2*pi*f_pass*n));

% Вариант 5: синус около первой зоны подавления
% n = (0:num_samples-1).';
% amp = 1000;
% f_stop = 1 / (cfg.R * cfg.M);
% f_near_stop = 0.95 * f_stop;
% x = round(amp * sin(2*pi*f_near_stop*n));

% Вариант 6: псевдослучайный signed-сигнал малой амплитуды
% rng(1);
% x = randi([-100, 100], num_samples, 1);

% -------------------------
% Запуск golden model
% -------------------------
[y, info] = cic_golden_fixed(x, cfg);

% -------------------------
% Вывод краткой информации в консоль
% -------------------------
fprintf("CIC golden model выполнена.\n");
fprintf("R = %d, M = %d, N = %d\n", cfg.R, cfg.M, cfg.N);
fprintf("gain = %d\n", info.gain);
fprintf("full_width = %d\n", info.full_width);
fprintf("output_width = %d\n", info.output_width);
fprintf("decimation_phase = %d\n", info.decimation_phase);
fprintf("input length = %d\n", length(x));
fprintf("output length = %d\n", length(y));