function cic_plot_debug(x_in, y_out, info, cfg)
% CIC_PLOT_DEBUG Отладочная визуализация сигналов CIC golden model.
%
% Эта функция вызывается из cic_golden_fixed.m только если:
%   cfg.PLOT_ENABLE = true;
%
% Если cfg.PLOT_ENABLE = false, графики не строятся.
%
% Режимы отображения:
%
%   cfg.PLOT_INTERNAL = true
%       строятся 5 графиков:
%       1. входной сигнал;
%       2. сигнал после цепочки интеграторов;
%       3. сигнал после децимации;
%       4. сигнал после comb-секций;
%       5. итоговый выход.
%
%   cfg.PLOT_INTERNAL = false
%       строятся только 2 графика:
%       1. входной сигнал;
%       2. итоговый выход.
%
%   cfg.PLOT_MAX_SAMPLES
%       ограничивает количество отображаемых отсчётов.
%       Это нужно, чтобы не рисовать слишком длинные последовательности.
%
% Функция предназначена только для отладки и визуального анализа.
% В массовых тестах PLOT_ENABLE лучше оставлять false.

    max_samples = cfg.PLOT_MAX_SAMPLES;

    % Ограничиваем количество отображаемых отсчётов,
    % чтобы графики не становились нечитаемыми.
    x_plot = limit_vector(x_in, max_samples);
    y_int_plot = limit_vector(info.after_integrators, max_samples);
    y_dec_plot = limit_vector(info.after_decimator, max_samples);
    y_comb_plot = limit_vector(info.after_combs, max_samples);
    y_out_plot = limit_vector(y_out, max_samples);

    fig_name = sprintf( ...
        "CIC debug: R=%d, M=%d, N=%d, IN=%d, OUT=%d, mode=%s", ...
        cfg.R, cfg.M, cfg.N, cfg.IN_WIDTH, cfg.OUT_WIDTH, cfg.OUTPUT_MODE);

    figure('Name', fig_name, 'NumberTitle', 'off');

    if cfg.PLOT_INTERNAL
        % ============================================================
        % Полный отладочный вид: вход + внутренние сигналы + выход
        % ============================================================

        subplot(5, 1, 1);
        plot(x_plot, '-o');
        grid on;
        title("Входной сигнал");
        xlabel("Номер входного отсчёта");
        ylabel("x[n]");

        subplot(5, 1, 2);
        plot(y_int_plot, '-o');
        grid on;
        title("После цепочки интеграторов");
        xlabel("Номер входного отсчёта");
        ylabel("y_{int}");

        subplot(5, 1, 3);
        stem(y_dec_plot, 'filled');
        grid on;
        title(sprintf("После децимации, phase = %d", info.decimation_phase));
        xlabel("Номер выходного отсчёта после децимации");
        ylabel("y_{dec}");

        subplot(5, 1, 4);
        stem(y_comb_plot, 'filled');
        grid on;
        title("После цепочки comb-секций");
        xlabel("Номер выходного отсчёта");
        ylabel("y_{comb}");

        subplot(5, 1, 5);
        stem(y_out_plot, 'filled');
        grid on;
        title("Итоговый выход golden model");
        xlabel("Номер выходного отсчёта");
        ylabel("y_{out}");

    else
        % ============================================================
        % Короткий отладочный вид: только вход и итоговый выход
        % ============================================================

        subplot(2, 1, 1);
        plot(x_plot, '-o');
        grid on;
        title("Входной сигнал");
        xlabel("Номер входного отсчёта");
        ylabel("x[n]");

        subplot(2, 1, 2);
        stem(y_out_plot, 'filled');
        grid on;
        title("Итоговый выход golden model");
        xlabel("Номер выходного отсчёта");
        ylabel("y_{out}");
    end

    % Общая подпись с параметрами модели
    sgtitle(sprintf( ...
        "CIC: R=%d, M=%d, N=%d, gain=%d, full width=%d, output width=%d", ...
        cfg.R, cfg.M, cfg.N, info.gain, info.full_width, info.output_width));
end

function y = limit_vector(x, max_samples)
% LIMIT_VECTOR Возвращает первые max_samples отсчётов вектора.
%
% Нужна только для визуализации, чтобы не строить слишком длинные графики.

    x = x(:);

    if length(x) > max_samples
        y = x(1:max_samples);
    else
        y = x;
    end
end