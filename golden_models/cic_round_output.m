function y = cic_round_output(x_full, full_width, out_width, round_mode)
% CIC_ROUND_OUTPUT Приведение разрядности к OUT_WIDTH.
%
% Если out_width < full_width, выполняется уменьшение разрядности
% с выбранным режимом округления.
%
% Если out_width >= full_width, значение просто приводится к новому
% знаковому диапазону, что соответствует знаковому расширению.

    round_mode = string(round_mode);

    % Количество младших бит, которые нужно убрать
    shift = full_width - out_width;

    if shift <= 0
        % OUT_WIDTH больше или равен текущей ширине:
        % численное значение не меняется, происходит знаковое расширение.
        y = cic_wrap_signed(x_full, out_width);
        return;
    end

    scale = 2^shift;

    switch round_mode
        case "trunc"
            y = floor(x_full / scale);

        case "ceil"
            y = ceil(x_full / scale);

        case "fix"
            y = fix(x_full / scale);

        otherwise
            error("Неизвестный режим округления: %s", round_mode);
    end

    y = cic_wrap_signed(y, out_width);
end