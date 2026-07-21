function [y_out, info] = cic_golden_fixed(x_in, cfg)
% CIC_GOLDEN_FIXED Эталонная fixed-point модель CIC-дециматора.
%
% Структура фильтра:
%   N интеграторов -> децимация на R -> N comb-секций ->
%   нормировка при необходимости -> приведение выходной разрядности
%
% Формат данных:
%   знаковый целочисленный формат в дополнительном коде.
%
% Переполнение:
%   wrap-around после каждой арифметической операции.
%
% Hogenauer pruning:
%   в текущей версии не реализован. Все внутренние стадии имеют
%   постоянную полную разрядность.
%
% DECIMATION_PHASE:
%   необязательный параметр cfg.DECIMATION_PHASE.
%   Если он не задан, используется фаза R:
%       y_dec = y_int(R:R:end)
%   Это основной вариант для RTL.
%   Для сравнения с dsp.CICDecimator можно перебирать фазы 1..R.
%
% Отладочные графики:
%   cfg.PLOT_ENABLE = true  - включить построение графиков;
%   cfg.PLOT_ENABLE = false - выключить построение графиков.
%
%   cfg.PLOT_INTERNAL = true  - показать внутренние сигналы;
%   cfg.PLOT_INTERNAL = false - показать только вход и выход.

    cfg = cic_validate_cfg(cfg);

    R = cfg.R;
    M = cfg.M;
    N = cfg.N;

    % Коэффициент усиления CIC-фильтра
    info.gain = (R * M)^N;

    % Прирост разрядности из-за усиления CIC
    info.growth_width = ceil(N * log2(R * M));

    % Полная внутренняя/выходная разрядность без потери значащих битов
    info.full_width = cfg.IN_WIDTH + info.growth_width;

    % В первой версии Hogenauer pruning не используется,
    % поэтому все внутренние стадии имеют одинаковую полную разрядность
    internal_width = info.full_width;
    info.internal_width = internal_width;

    % Приведение входа к диапазону знакового числа IN_WIDTH
    x = cic_wrap_signed(double(x_in(:)), cfg.IN_WIDTH);

    % -------------------------
    % Цепочка интеграторов
    % -------------------------
    int_states = zeros(N, 1);
    y_int = zeros(size(x));

    for i = 1:length(x)
        sample = x(i);

        for st = 1:N
            % Интегратор:
            %   y[n] = y[n-1] + x[n]
            %
            % После сложения выполняется wrap-around,
            % чтобы смоделировать переполнение в дополнительном коде.
            int_states(st) = cic_wrap_signed(int_states(st) + sample, internal_width);
            sample = int_states(st);
        end

        y_int(i) = sample;
    end

    info.after_integrators = y_int;

    % -------------------------
    % Децимация на R
    % -------------------------
    % По умолчанию первый выходной отсчёт формируется на R-м входном отсчёте.
    % Это основная фаза, которую планируется использовать для RTL.
    %
    % Для справочного сравнения с dsp.CICDecimator можно задать:
    %   cfg.DECIMATION_PHASE = 1..R
    % и проверить другие фазы.
    if isfield(cfg, "DECIMATION_PHASE")
        decimation_phase = cfg.DECIMATION_PHASE;
    else
        decimation_phase = R;
    end

    assert(decimation_phase >= 1 && decimation_phase <= R, ...
        "DECIMATION_PHASE должен быть в диапазоне 1..R");

    y_dec = y_int(decimation_phase:R:end);

    info.after_decimator = y_dec;
    info.decimation_phase = decimation_phase;

    % -------------------------
    % Цепочка comb-секций
    % -------------------------
    y_comb = y_dec;

    for st = 1:N
        delay_line = zeros(M, 1);
        stage_out = zeros(size(y_comb));

        for i = 1:length(y_comb)
            current = y_comb(i);
            delayed = delay_line(end);

            % Comb-секция:
            %   y[n] = x[n] - x[n-M]
            %
            % После вычитания выполняется wrap-around.
            stage_out(i) = cic_wrap_signed(current - delayed, internal_width);

            % Обновление линии задержки
            delay_line = [current; delay_line(1:end-1)];
        end

        y_comb = stage_out;
    end

    info.after_combs = y_comb;

    % -------------------------
    % Нормировка выходного сигнала
    % -------------------------
    y_full = y_comb;

    % Текущая эффективная разрядность результата.
    % До нормировки она равна полной внутренней разрядности.
    current_width = info.full_width;

    if cfg.NORMALIZE
        % Пока нормировка реализована только для случая,
        % когда коэффициент усиления является степенью двойки.
        % Тогда деление можно заменить арифметическим сдвигом.
        k = log2(info.gain);

        if abs(k - round(k)) > 1e-12
            error("Нормировка пока реализована только для gain, равного степени двойки.");
        end

        shift_norm = round(k);

        % Модель поведения арифметического сдвига вправо:
        % для отрицательных чисел используется floor.
        y_full = floor(y_full / 2^shift_norm);

        info.normalization_shift = shift_norm;

        % После нормировки эффективная разрядность уменьшается.
        % Например:
        %   FULL_WIDTH = 20
        %   gain = 16 = 2^4
        %   после нормировки effective_width = 20 - 4 = 16
        current_width = info.full_width - shift_norm;
    else
        info.normalization_shift = 0;
    end

    info.current_width_after_normalization = current_width;

    % -------------------------
    % Формирование выходной разрядности
    % -------------------------
    switch cfg.OUTPUT_MODE
        case "full"
            % Полная выходная разрядность текущего результата.
            % Если нормировка выключена, это FULL_WIDTH.
            % Если нормировка включена, это FULL_WIDTH - normalization_shift.
            y_out = cic_wrap_signed(y_full, current_width);
            info.output_width = current_width;

        case "custom"
            % Неполная выходная разрядность OUT_WIDTH
            % с выбранным режимом округления.
            %
            % Важно: если была нормировка, приводим не от исходного FULL_WIDTH,
            % а от текущей эффективной разрядности после нормировки.
            y_out = cic_round_output(y_full, current_width, cfg.OUT_WIDTH, cfg.ROUND_MODE);
            info.output_width = cfg.OUT_WIDTH;

        otherwise
            error("Неизвестный режим OUTPUT_MODE: %s", cfg.OUTPUT_MODE);
    end

    % -------------------------
    % Отладочная визуализация
    % -------------------------
    % По умолчанию cfg.PLOT_ENABLE = false.
    %
    % Чтобы включить графики, в тестовом скрипте нужно задать:
    %   cfg.PLOT_ENABLE = true;
    %
    % Чтобы выключить графики:
    %   cfg.PLOT_ENABLE = false;
    %
    % Чтобы рисовать внутренние сигналы:
    %   cfg.PLOT_INTERNAL = true;
    %
    % Чтобы рисовать только вход и выход:
    %   cfg.PLOT_INTERNAL = false;
    if cfg.PLOT_ENABLE
        cic_plot_debug(x, y_out, info, cfg);
    end
end