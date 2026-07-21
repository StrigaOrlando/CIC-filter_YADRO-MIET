function test_normalization()
% TEST_NORMALIZATION Проверка нормировки.
%
% Для R=4, M=1, N=2 коэффициент усиления gain = 16 = 2^4.
% При включённой нормировке постоянный вход 100 после переходного процесса
% должен снова стать 100.

    fprintf("3. Проверка нормировки...\n");

    cfg = make_cfg(16, 16, 4, 1, 2, "custom", "trunc", true);

    x_value = 100;
    num_samples = 64;
    x = x_value * ones(num_samples, 1);

    [y, info] = cic_golden_fixed(x, cfg);

    fprintf("   gain = %d\n", info.gain);
    fprintf("   normalization_shift = %d\n", info.normalization_shift);
    fprintf("   первые значения выхода после нормировки:\n");
    disp(y(1:min(12, length(y))).');

    steady_part = y(end-5:end);

    if any(steady_part ~= x_value)
        error("Нормировка: после переходного процесса выход не равен входному значению %d.", x_value);
    end

    fprintf("   OK: после нормировки установившееся значение равно %d.\n\n", x_value);
end