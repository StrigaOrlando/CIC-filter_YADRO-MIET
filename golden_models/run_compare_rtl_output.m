clear; clc; close all;

% ============================================================
% Сравнение RTL-выхода с MATLAB golden model
%
% Ожидаемая структура папки:
%
% rtl_test_case/
%   expected_output.txt   - эталонный выход MATLAB
%   rtl_output.txt        - выход RTL testbench
%
% Формат файлов:
%   одно целое число в одной строке
% ============================================================

case_dir = "rtl_test_case";

expected_file = fullfile(case_dir, "expected_output.txt");
rtl_file      = fullfile(case_dir, "rtl_output.txt");

% ============================================================
% 1. Проверка наличия файлов
% ============================================================

if ~exist(expected_file, "file")
    error("Не найден файл эталона MATLAB: %s", expected_file);
end

if ~exist(rtl_file, "file")
    error("Не найден файл выхода RTL: %s", rtl_file);
end

% ============================================================
% 2. Чтение файлов
% ============================================================

expected = read_vector_txt(expected_file);
rtl_out  = read_vector_txt(rtl_file);

% ============================================================
% 3. Сравнение
% ============================================================

result = compare_vectors(expected, rtl_out);

% ============================================================
% 4. Вывод результата
% ============================================================

fprintf("Сравнение RTL output с MATLAB golden model\n");
fprintf("Папка теста: %s\n", case_dir);
fprintf("\n");

fprintf("Длина expected_output = %d\n", result.expected_len);
fprintf("Длина rtl_output      = %d\n", result.rtl_len);
fprintf("Сравнено отсчётов     = %d\n", result.compare_len);
fprintf("\n");

if result.length_match
    fprintf("Длины файлов совпадают.\n");
else
    fprintf("WARNING: длины файлов не совпадают.\n");
end

if result.full_match
    fprintf("OK: RTL output полностью совпадает с MATLAB golden model.\n");
else
    fprintf("ERROR: RTL output НЕ совпадает с MATLAB golden model.\n");
    fprintf("Количество несовпадающих отсчётов = %d\n", result.num_mismatches);
    fprintf("Первая ошибка на индексе          = %d\n", result.first_mismatch_index);
    fprintf("Ожидалось MATLAB                  = %d\n", result.first_expected_value);
    fprintf("Получено RTL                      = %d\n", result.first_rtl_value);
    fprintf("Ошибка RTL - MATLAB               = %d\n", result.first_error_value);
    fprintf("\n");
    fprintf("max abs error = %g\n", result.max_abs_error);
    fprintf("rms error     = %g\n", result.rms_error);
end

% ============================================================
% 5. График ошибки, если есть несовпадения
% ============================================================

if ~result.full_match
    figure('Name', 'RTL vs MATLAB comparison', 'NumberTitle', 'off');

    subplot(3, 1, 1);
    stem(expected(1:result.compare_len), 'filled');
    grid on;
    title("MATLAB expected output");
    xlabel("Номер выходного отсчёта");
    ylabel("expected");

    subplot(3, 1, 2);
    stem(rtl_out(1:result.compare_len), 'filled');
    grid on;
    title("RTL output");
    xlabel("Номер выходного отсчёта");
    ylabel("rtl");

    subplot(3, 1, 3);
    stem(result.error_vector, 'filled');
    grid on;
    title("Ошибка: RTL - MATLAB");
    xlabel("Номер выходного отсчёта");
    ylabel("error");
end