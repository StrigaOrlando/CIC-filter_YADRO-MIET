function result = compare_vectors(expected, rtl_out)
% COMPARE_VECTORS Побитовое/целочисленное сравнение двух векторов.
%
% expected - эталонный выход MATLAB golden model
% rtl_out  - выход RTL testbench
%
% Сравнение выполняется по общему участку длины:
%   min(length(expected), length(rtl_out))
%
% Если длины разные, это отдельно фиксируется в result.length_match.

    expected = expected(:);
    rtl_out = rtl_out(:);

    result.expected_len = length(expected);
    result.rtl_len = length(rtl_out);
    result.compare_len = min(result.expected_len, result.rtl_len);

    result.length_match = (result.expected_len == result.rtl_len);

    exp_cmp = expected(1:result.compare_len);
    rtl_cmp = rtl_out(1:result.compare_len);

    error_vector = rtl_cmp - exp_cmp;

    result.error_vector = error_vector;

    mismatch_mask = (error_vector ~= 0);

    result.num_mismatches = sum(mismatch_mask);
    result.full_match = result.length_match && (result.num_mismatches == 0);

    result.max_abs_error = max(abs(error_vector));
    result.rms_error = sqrt(mean(double(error_vector).^2));

    if result.num_mismatches > 0
        idx = find(mismatch_mask, 1, 'first');

        result.first_mismatch_index = idx;
        result.first_expected_value = exp_cmp(idx);
        result.first_rtl_value = rtl_cmp(idx);
        result.first_error_value = error_vector(idx);
    else
        result.first_mismatch_index = [];
        result.first_expected_value = [];
        result.first_rtl_value = [];
        result.first_error_value = [];
    end
end