function [best_lag, best_max_err, best_rms_err, best_rel_max_err, best_rel_rms_err] = ...
    find_best_lag(y1, y2, max_lag, skip)
% FIND_BEST_LAG Поиск лучшего лага для сравнения двух последовательностей.
%
% Используется для сравнения нашей golden model с dsp.CICDecimator.
%
% Входы:
%   y1      - первая последовательность
%   y2      - вторая последовательность
%   max_lag - максимальный лаг для перебора
%   skip    - сколько первых отсчётов пропустить после выравнивания
%
% Выходы:
%   best_lag         - лучший найденный лаг
%   best_max_err     - максимальная абсолютная ошибка
%   best_rms_err     - среднеквадратическая ошибка
%   best_rel_max_err - max error относительно масштаба сигнала
%   best_rel_rms_err - rms error относительно масштаба сигнала
%
% Лаг определяется так:
%   lag > 0 означает, что y1 сдвигается вперёд относительно y2;
%   lag < 0 означает, что y2 сдвигается вперёд относительно y1.
%
% Лучший лаг выбирается по минимальной относительной RMS-ошибке,
% потому что max error может быть большим из-за одного переходного отсчёта.

    best_lag = 0;
    best_max_err = inf;
    best_rms_err = inf;
    best_rel_max_err = inf;
    best_rel_rms_err = inf;

    y1 = double(y1(:));
    y2 = double(y2(:));

    for lag = -max_lag:max_lag

        % -------------------------
        % Выравнивание по лагу
        % -------------------------
        if lag >= 0
            a = y1(1+lag:end);
            b = y2(1:end-lag);
        else
            a = y1(1:end+lag);
            b = y2(1-lag:end);
        end

        % Приводим к общей длине
        len = min(length(a), length(b));

        if len == 0
            continue;
        end

        a = a(1:len);
        b = b(1:len);

        % Пропускаем начальные отсчёты после выравнивания
        if length(a) <= skip
            continue;
        end

        a = a(skip+1:end);
        b = b(skip+1:end);

        % -------------------------
        % Ошибки
        % -------------------------
        err_vec = a - b;

        max_err = max(abs(err_vec));
        rms_err = sqrt(mean(err_vec.^2));

        % Масштаб сигнала для относительной ошибки.
        % Берём максимум из амплитуд двух сигналов,
        % чтобы не делить на слишком маленькое число.
        signal_scale = max([max(abs(a)), max(abs(b)), 1]);

        rel_max_err = max_err / signal_scale;
        rel_rms_err = rms_err / signal_scale;

        % Лучший лаг выбираем по RMS-ошибке,
        % потому что она лучше отражает среднюю близость сигналов.
        if rel_rms_err < best_rel_rms_err
            best_lag = lag;
            best_max_err = max_err;
            best_rms_err = rms_err;
            best_rel_max_err = rel_max_err;
            best_rel_rms_err = rel_rms_err;
        end
    end

    if isinf(best_rel_rms_err)
        error("Не удалось найти корректный лаг для сравнения последовательностей.");
    end
end