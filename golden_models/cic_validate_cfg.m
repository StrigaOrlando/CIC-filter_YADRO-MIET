function cfg = cic_validate_cfg(cfg)
% CIC_VALIDATE_CFG Проверка параметров модели CIC-фильтра.
%
% Проверяются ограничения из текущей версии ТЗ:
%   IN_WIDTH: 10..20
%   R: 2..700
%   N: 2..6
%   M: 1 или 2
%
% Дополнительно:
%   DECIMATION_PHASE, если задан, должен быть в диапазоне 1..R.
%
% Отладочная визуализация:
%   PLOT_ENABLE      - включить/выключить построение графиков.
%   PLOT_INTERNAL    - рисовать только вход/выход или ещё внутренние сигналы.
%   PLOT_MAX_SAMPLES - сколько отсчётов максимум показывать на графиках.

    required_fields = ["IN_WIDTH", "OUT_WIDTH", "R", "M", "N", ...
                       "OUTPUT_MODE", "ROUND_MODE", "NORMALIZE"];

    for k = 1:length(required_fields)
        if ~isfield(cfg, required_fields(k))
            error("В cfg отсутствует поле: %s", required_fields(k));
        end
    end

    assert(cfg.IN_WIDTH >= 10 && cfg.IN_WIDTH <= 20, ...
        "IN_WIDTH должен быть в диапазоне 10..20");

    assert(cfg.OUT_WIDTH >= 1, ...
        "OUT_WIDTH должен быть положительным");

    assert(cfg.R >= 2 && cfg.R <= 700, ...
        "R должен быть в диапазоне 2..700");

    assert(cfg.N >= 2 && cfg.N <= 6, ...
        "N должен быть в диапазоне 2..6");

    assert(cfg.M == 1 || cfg.M == 2, ...
        "M должен быть равен 1 или 2");

    cfg.OUTPUT_MODE = string(cfg.OUTPUT_MODE);
    cfg.ROUND_MODE = string(cfg.ROUND_MODE);

    assert(any(cfg.OUTPUT_MODE == ["full", "custom"]), ...
        "OUTPUT_MODE должен быть 'full' или 'custom'");

    assert(any(cfg.ROUND_MODE == ["trunc", "ceil", "fix"]), ...
        "ROUND_MODE должен быть 'trunc', 'ceil' или 'fix'");

    assert(islogical(cfg.NORMALIZE) || isnumeric(cfg.NORMALIZE), ...
        "NORMALIZE должен быть true/false");

    cfg.NORMALIZE = logical(cfg.NORMALIZE);

    % -------------------------
    % Необязательная фаза децимации
    % -------------------------
    % Если DECIMATION_PHASE не задан, в cic_golden_fixed будет использоваться R.
    % Это основной вариант для RTL: первый выходной отсчёт формируется на R-м входном отсчёте.
    %
    % DECIMATION_PHASE нужен в основном для справочного сравнения с dsp.CICDecimator,
    % потому что встроенный MATLAB-объект может использовать другую фазу.
    if isfield(cfg, "DECIMATION_PHASE")
        assert(cfg.DECIMATION_PHASE >= 1 && cfg.DECIMATION_PHASE <= cfg.R, ...
            "DECIMATION_PHASE должен быть в диапазоне 1..R");
    end

    % -------------------------
    % Необязательные параметры отладочной визуализации
    % -------------------------
    % По умолчанию графики выключены, чтобы массовые тесты
    % не открывали много окон.
    if ~isfield(cfg, "PLOT_ENABLE")
        cfg.PLOT_ENABLE = false;
    end

    % Если PLOT_INTERNAL = true, строятся графики:
    %   вход;
    %   после интеграторов;
    %   после децимации;
    %   после comb;
    %   итоговый выход.
    %
    % Если PLOT_INTERNAL = false, строятся только:
    %   вход;
    %   итоговый выход.
    if ~isfield(cfg, "PLOT_INTERNAL")
        cfg.PLOT_INTERNAL = true;
    end

    % Ограничение количества отображаемых отсчётов.
    % Нужно, чтобы графики не становились нечитаемыми.
    if ~isfield(cfg, "PLOT_MAX_SAMPLES")
        cfg.PLOT_MAX_SAMPLES = 300;
    end

    cfg.PLOT_ENABLE = logical(cfg.PLOT_ENABLE);
    cfg.PLOT_INTERNAL = logical(cfg.PLOT_INTERNAL);

    assert(cfg.PLOT_MAX_SAMPLES >= 1, ...
        "PLOT_MAX_SAMPLES должен быть положительным");
end