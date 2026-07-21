function test_output_rounding()
% TEST_OUTPUT_ROUNDING Проверка режимов округления.
%
% Проверяются режимы:
%   trunc - усечение / arithmetic shift / floor
%   ceil  - округление в +inf
%   fix   - округление к нулю

    fprintf("2. Проверка режимов округления...\n");

    full_width = 8;
    out_width = 5;

    % shift = 8 - 5 = 3, то есть деление на 8.
    % Значения подобраны так, чтобы были видны различия
    % для положительных и отрицательных чисел.
    x_full = [-17; -16; -15; -13; -9; -8; -7; -1; ...
               0;   1;   7;   8;  9; 13; 15; 16; 17];

    y_trunc = cic_round_output(x_full, full_width, out_width, "trunc");
    y_ceil  = cic_round_output(x_full, full_width, out_width, "ceil");
    y_fix   = cic_round_output(x_full, full_width, out_width, "fix");

    scale = 2^(full_width - out_width);

    ref_trunc = cic_wrap_signed(floor(x_full / scale), out_width);
    ref_ceil  = cic_wrap_signed(ceil(x_full / scale),  out_width);
    ref_fix   = cic_wrap_signed(fix(x_full / scale),   out_width);

    if ~isequal(y_trunc, ref_trunc)
        error("Ошибка в режиме округления trunc.");
    end

    if ~isequal(y_ceil, ref_ceil)
        error("Ошибка в режиме округления ceil.");
    end

    if ~isequal(y_fix, ref_fix)
        error("Ошибка в режиме округления fix.");
    end

    result_table = table(x_full, y_trunc, y_ceil, y_fix, ...
        'VariableNames', {'x_full', 'trunc', 'ceil', 'fix'});

    disp(result_table);

    fprintf("   OK: все режимы округления работают корректно.\n\n");
end