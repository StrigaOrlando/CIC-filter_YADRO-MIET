function test_constant_input()
% TEST_CONSTANT_INPUT Проверка постоянного входа.
%
% Для постоянного входа после переходного процесса выход CIC
% должен установиться на уровне input_value * gain.

    fprintf("1. Проверка постоянного входа...\n");

    cfg = make_cfg(16, 16, 4, 1, 2, "full", "trunc", false);

    x_value = 100;
    num_samples = 64;
    x = x_value * ones(num_samples, 1);

    [y, info] = cic_golden_fixed(x, cfg);

    expected_steady = x_value * info.gain;

    fprintf("   gain = %d\n", info.gain);
    fprintf("   ожидаемое установившееся значение = %d\n", expected_steady);
    fprintf("   первые значения выхода:\n");
    disp(y(1:min(12, length(y))).');

    steady_part = y(end-5:end);

    if any(steady_part ~= expected_steady)
        error("Постоянный вход: выход не вышел на ожидаемое значение %d.", expected_steady);
    end

    fprintf("   OK: после переходного процесса выход равен %d.\n\n", expected_steady);
end