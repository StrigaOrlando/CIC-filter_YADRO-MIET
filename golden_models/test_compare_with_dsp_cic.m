function test_compare_with_dsp_cic()
% TEST_COMPARE_WITH_DSP_CIC Дополнительное сравнение с dsp.CICDecimator.
%
% Этот тест не является основным эталоном для RTL.
% Основной эталон для RTL — наша fixed-point golden model.
%
% dsp.CICDecimator используется только как справочная проверка.
% Отличия возможны из-за:
%   - другой фазы децимации;
%   - других начальных условий;
%   - другой fixed-point трактовки;
%   - отличий во внутреннем формате данных System object.
%
% В этой версии для нашей модели перебирается DECIMATION_PHASE = 1..R,
% чтобы понять, какая фаза децимации ближе всего к dsp.CICDecimator.

    fprintf("4. Сравнение с dsp.CICDecimator...\n");

    % Проверяем наличие DSP System Toolbox
    if exist("dsp.CICDecimator", "class") ~= 8
        fprintf("   DSP System Toolbox не найден. Тест пропущен.\n\n");
        return;
    end

    % Маленькая конфигурация для анализа
    cfg_base = make_cfg(16, 16, 4, 1, 2, "full", "trunc", false);

    num_samples = 256;

    % -------------------------
    % Набор входных воздействий
    % -------------------------
    input_tests = {};

    % 1. Постоянный вход
    input_tests{end+1} = struct( ...
        "name", "constant_100", ...
        "x", 100 * ones(num_samples, 1));

    % 2. Одиночный импульс
    x_imp = zeros(num_samples, 1);
    x_imp(1) = 100;

    input_tests{end+1} = struct( ...
        "name", "single_impulse_100", ...
        "x", x_imp);

    % 3. Малый случайный signed-сигнал
    rng(2);
    x_rand_small = randi([-100, 100], num_samples, 1);

    input_tests{end+1} = struct( ...
        "name", "random_small", ...
        "x", x_rand_small);

    % 4. Full-range random, только как стресс-сравнение
    rng(3);
    in_min = -2^(cfg_base.IN_WIDTH - 1);
    in_max =  2^(cfg_base.IN_WIDTH - 1) - 1;
    x_rand_full = randi([in_min, in_max], num_samples, 1);

    input_tests{end+1} = struct( ...
        "name", "random_full_range_stress", ...
        "x", x_rand_full);

    % -------------------------
    % Прогон всех воздействий
    % -------------------------
    for test_idx = 1:length(input_tests)

        test_name = input_tests{test_idx}.name;
        x = input_tests{test_idx}.x;

        fprintf("   --- Тест: %s ---\n", test_name);

        % Встроенная MATLAB-модель CIC.
        % Создаём объект заново для каждого теста, чтобы начальные состояния
        % точно были нулевыми.
        cic_ref = dsp.CICDecimator( ...
            cfg_base.R, ...
            cfg_base.M, ...
            cfg_base.N, ...
            'FixedPointDataType', 'Full precision');

        y_ref = cic_ref(int16(x));
        y_ref = double(y_ref);

        % Перебираем фазы нашей модели
        best_overall = struct();
        best_overall.rel_rms_err = inf;

        for phase = 1:cfg_base.R

            cfg = cfg_base;
            cfg.DECIMATION_PHASE = phase;

            [y_our, info] = cic_golden_fixed(x, cfg);

            % Из-за разной фазы длины могут отличаться на 1.
            % find_best_lag внутри всё равно приведёт к общей длине.
            max_lag = 10;
            skip = min(8, floor(min(length(y_our), length(y_ref))/4));

            [best_lag, best_max_err, best_rms_err, best_rel_max_err, best_rel_rms_err] = ...
                find_best_lag(y_our, y_ref, max_lag, skip);

            if best_rel_rms_err < best_overall.rel_rms_err
                best_overall.phase = phase;
                best_overall.lag = best_lag;
                best_overall.max_err = best_max_err;
                best_overall.rms_err = best_rms_err;
                best_overall.rel_max_err = best_rel_max_err;
                best_overall.rel_rms_err = best_rel_rms_err;
                best_overall.y_our_len = length(y_our);
                best_overall.y_ref_len = length(y_ref);
                best_overall.max_abs_y_our = max(abs(y_our));
                best_overall.max_abs_y_ref = max(abs(y_ref));
                best_overall.info = info;
            end
        end

        fprintf("      full_width нашей модели = %d\n", best_overall.info.full_width);
        fprintf("      лучшая DECIMATION_PHASE нашей модели = %d\n", best_overall.phase);
        fprintf("      DECIMATION_PHASE для RTL по умолчанию = %d\n", cfg_base.R);
        fprintf("      длина выхода нашей модели = %d\n", best_overall.y_our_len);
        fprintf("      длина выхода dsp.CICDecimator = %d\n", best_overall.y_ref_len);
        fprintf("      max abs нашей модели = %g\n", best_overall.max_abs_y_our);
        fprintf("      max abs dsp.CICDecimator = %g\n", best_overall.max_abs_y_ref);
        fprintf("      лучший лаг = %d выходных отсчётов\n", best_overall.lag);
        fprintf("      max abs error после выравнивания = %g\n", best_overall.max_err);
        fprintf("      rms error после выравнивания = %g\n", best_overall.rms_err);
        fprintf("      относительная max error = %.6f %%\n", 100 * best_overall.rel_max_err);
        fprintf("      относительная rms error = %.6f %%\n", 100 * best_overall.rel_rms_err);

        if best_overall.rel_rms_err < 1e-6
            fprintf("      OK: при подборе фазы отличие от dsp.CICDecimator пренебрежимо мало.\n");

        elseif best_overall.rel_rms_err < 0.01
            fprintf("      INFO: отличие небольшое, менее 1%% по RMS.\n");
            fprintf("      Для справочного сравнения это допустимо.\n");

        else
            fprintf("      INFO: отличие заметное даже после подбора фазы.\n");
            fprintf("      Это не считается ошибкой golden model, так как RTL должен сравниваться именно с нашей моделью.\n");
            fprintf("      Возможные причины: fixed-point трактовка, переполнения, начальные условия dsp.CICDecimator.\n");
        end

        fprintf("\n");
    end
end