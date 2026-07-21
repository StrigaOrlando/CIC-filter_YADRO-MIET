function tests = make_test_inputs(cfg, num_samples)
% MAKE_TEST_INPUTS Генерация входных воздействий для CIC-фильтра.
%
% Формируются воздействия из текущего ТЗ:
%   1. нулевой вход
%   2. постоянный вход
%   3. одиночный импульс
%   4. ступенька
%   5. синус в полосе пропускания
%   6. синус около первой зоны подавления
%   7. псевдослучайный signed-сигнал
%   8. максимальные положительные и отрицательные значения

    tests = {};

    in_min = -2^(cfg.IN_WIDTH - 1);
    in_max =  2^(cfg.IN_WIDTH - 1) - 1;

    n = (0:num_samples-1).';

    % -------------------------
    % 1. Нулевой вход
    % -------------------------
    tests{end+1} = struct( ...
        "name", "zero_input", ...
        "x", zeros(num_samples, 1));

    % -------------------------
    % 2. Постоянный вход
    % -------------------------
    const_value = round(0.1 * in_max);

    tests{end+1} = struct( ...
        "name", "constant_input", ...
        "x", const_value * ones(num_samples, 1));

    % -------------------------
    % 3. Одиночный импульс
    % -------------------------
    x_imp = zeros(num_samples, 1);
    x_imp(1) = const_value;

    tests{end+1} = struct( ...
        "name", "single_impulse", ...
        "x", x_imp);

    % -------------------------
    % 4. Ступенька
    % -------------------------
    x_step = zeros(num_samples, 1);
    x_step(floor(num_samples/4):end) = const_value;

    tests{end+1} = struct( ...
        "name", "step_input", ...
        "x", x_step);

    % -------------------------
    % 5. Синус в полосе пропускания
    % -------------------------
    % Частота задана относительно входной частоты дискретизации.
    % Берём частоту заметно ниже выходной полосы после децимации.
    amp = round(0.25 * in_max);
    f_pass = 1 / (16 * cfg.R);

    x_sin_pass = round(amp * sin(2*pi*f_pass*n));

    tests{end+1} = struct( ...
        "name", "sine_passband", ...
        "x", x_sin_pass);

    % -------------------------
    % 6. Синус около первой зоны подавления
    % -------------------------
    % Для CIC нули АЧХ расположены около частот k/(R*M)
    % относительно входной частоты дискретизации.
    f_stop = 1 / (cfg.R * cfg.M);

    % Берём частоту рядом с первым нулём, но не строго в нуле.
    f_near_stop = 0.95 * f_stop;

    x_sin_stop = round(amp * sin(2*pi*f_near_stop*n));

    tests{end+1} = struct( ...
        "name", "sine_near_first_stopband", ...
        "x", x_sin_stop);

    % -------------------------
    % 7. Псевдослучайный signed-сигнал
    % -------------------------
    rng(1); % фиксируем seed для повторяемости тестов

    x_rand = randi([in_min, in_max], num_samples, 1);

    tests{end+1} = struct( ...
        "name", "random_signed", ...
        "x", x_rand);

    % -------------------------
    % 8. Максимальные положительные и отрицательные значения
    % -------------------------
    x_extreme = zeros(num_samples, 1);
    x_extreme(1:2:end) = in_max;
    x_extreme(2:2:end) = in_min;

    tests{end+1} = struct( ...
        "name", "max_min_alternating", ...
        "x", x_extreme);
end