function y = cic_wrap_signed(x, width)
% CIC_WRAP_SIGNED Приведение чисел к знаковому диапазону width бит.
%
% Моделирует поведение дополнительного кода при переполнении:
% если значение выходит за диапазон, оно возвращается в диапазон
% по правилу wrap-around.
%
% Диапазон:
%   -2^(width-1) ... 2^(width-1)-1

    min_val = -2^(width - 1);
    mod_val = 2^width;

    y = mod(round(x) - min_val, mod_val) + min_val;
end