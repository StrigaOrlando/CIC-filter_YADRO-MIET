function check_result(x, y, info, cfg, test_name)
% CHECK_RESULT Базовая проверка корректности результата golden model.
%
% Это не сравнение с RTL, а проверка самой MATLAB-модели:
%   - нет NaN/Inf;
%   - значения целочисленные;
%   - длина выхода соответствует децимации;
%   - выход не выходит за допустимый диапазон;
%   - промежуточные массивы имеют ожидаемые размеры.

    if any(isnan(y)) || any(isinf(y))
        error("В выходе теста %s есть NaN или Inf.", test_name);
    end

    if any(y ~= round(y))
        error("В выходе теста %s есть нецелые значения.", test_name);
    end

    expected_len = floor(length(x) / cfg.R);

    if length(y) ~= expected_len
        error("Некорректная длина выхода в тесте %s: получено %d, ожидалось %d.", ...
            test_name, length(y), expected_len);
    end

    out_min = -2^(info.output_width - 1);
    out_max =  2^(info.output_width - 1) - 1;

    if any(y < out_min) || any(y > out_max)
        error("Выход теста %s вышел за диапазон output_width.", test_name);
    end

    if length(info.after_integrators) ~= length(x)
        error("Некорректная длина after_integrators в тесте %s.", test_name);
    end

    if length(info.after_decimator) ~= expected_len
        error("Некорректная длина after_decimator в тесте %s.", test_name);
    end

    if length(info.after_combs) ~= expected_len
        error("Некорректная длина after_combs в тесте %s.", test_name);
    end
end