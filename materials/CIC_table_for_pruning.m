% CIC_Hogenauer_pruning_table.m
% Генерация таблицы прунинга Хогенауэра для всех заданных комбинаций.
% Результат записывается в CIC_pruning_table.txt

warning('off', 'MATLAB:nchoosek:LargeCoefficient');

% Диапазоны параметров
N_vals = 2:6;               % количество стадий (2..6)
%R_vals = 2:700;             % коэффициент децимации (2..700)
R_vals = [2, 4, 8, 16, 32, 64, 128, 256, 512, 700] % для тестировки
M_vals = [1, 2];            % дифференциальная задержка
Bin_vals = 10:20;           % разрядность входных данных
Bout_vals = 10:20;          % разрядность выходных данных

% Вспомогательный массив для комб-секций (до 7 каскадов)
F_sub_j_for_many_combs = sqrt([2, 6, 20, 70, 252, 924, 3432]);

% Открываем файл для записи
fid = fopen('CIC_pruning_table.txt', 'w');
if fid == -1
    error('Не удалось открыть файл для записи.');
end

% Заголовок
% fprintf(fid, 'N\tR\tM\tBin\tBout\tStage\tBj\tAccumWidth\n');

% Основной цикл по всем комбинациям
for N = N_vals
    for M = M_vals
        % Предварительно вычислим некоторые константы, не зависящие от R, Bin, Bout
        % Инициализируем массив F_sub_j (будем перезаписывать для каждого R)
        % но часть значений зависит только от N, M и R, поэтому вынесем то, что не зависит
        % из циклов по Bin/Bout.
        for R = R_vals
            % --- Расчет F_sub_j для данного N, R, M ---
            % 1) Интеграторы: j от N-1 до 1
            F_sub_j = zeros(1, 2*N+1);
            for j = N-1:-1:1
                h_sub_j = zeros(1, (R*M-1)*N + j);   % индексы 1..(R*M-1)*N+j
                for k = 0:(R*M-1)*N + j -1
                    for L = 0:floor(k/(R*M))
                        Change_to_Result = (-1)^L * nchoosek(N, L) ...
                                         * nchoosek(N-j + k - R*M*L, k - R*M*L);
                        h_sub_j(k+1) = h_sub_j(k+1) + Change_to_Result;
                    end
                end
                F_sub_j(j) = sqrt(sum(h_sub_j.^2));
            end
            % 2) Последний интегратор (j = N)
            F_sub_j(N) = F_sub_j_for_many_combs(N-1) * sqrt(R*M);
            % 3) Комб-секции (j = N+1 .. 2N)
            for j = 2*N:-1:N+1
                F_sub_j(j) = F_sub_j_for_many_combs(2*N - j + 1);
            end
            % 4) Финальный выходной регистр
            F_sub_j(2*N+1) = 1;

            % Вектор -log2(Fj)
            Minus_log2_F = -log2(F_sub_j)';  % столбец

            % Общий коэффициент усиления CIC
            CIC_gain = (R*M)^N;
            bits_growth = ceil(log2(CIC_gain));

            % Далее идут параметры Bin / Bout
            for Bin = Bin_vals
                % Полная разрядность без усечений
                num_out_bits_no_trunc = bits_growth + Bin;   % уравнение (11) с +Bin
                half_log_6_over_N = 0.5 * log2(6/N);

                for Bout = Bout_vals
                    % Разрядность отбрасываемая на выходе
                    out_trunc_bits = num_out_bits_no_trunc - Bout;
                    if out_trunc_bits < 0
                        out_trunc_bits = 0;   % нет усечения, если Bout больше полной разрядности
                    end
                    out_trunc_var = (2^out_trunc_bits)^2 / 12;
                    out_trunc_std = sqrt(out_trunc_var);
                    log2_out_std = log2(out_trunc_std);

                    % Вычисляем Bj для всех каскадов
                    Bj = floor(Minus_log2_F + log2_out_std + half_log_6_over_N);
                    % Корректировка: Bj не может быть отрицательным и не больше полной разрядности
                    Bj = max(Bj, 0);
                    Bj = min(Bj, num_out_bits_no_trunc);

                    % Ширина аккумуляторов для каскадов 1..2N
                    accum_width = num_out_bits_no_trunc - Bj;
                    % Финальная стадия
                    Bj_final = out_trunc_bits;   % для выходного усечения
                    accum_width_final = Bout;
                    
                    %=========================================================
                    % Вывод 1:
                    %=========================================================
                    % Заголовок
                    fprintf(fid, 'N\tR\tM\tBin\tBout\n');
                    fprintf(fid, '%d\t%d\t%d\t%d\t%d\n\n', ...
                            N, R, M, Bin, Bout);

                    % Stage
                    fprintf(fid, 'Stage      \t');
                    for stage = 1:2*N
                        fprintf(fid, '%d\t', stage);
                    end
                    fprintf(fid, '%d\n', 2*N+1);

                    % Bj
                    fprintf(fid, 'Bj         \t');
                    for stage = 1:2*N
                        fprintf(fid, '%d\t', Bj(stage));
                    end
                    fprintf(fid, '%d\n', Bj_final);

                    % AccumWidth
                    fprintf(fid, 'AccumWidth\t');
                    for stage = 1:2*N
                        fprintf(fid, '%d\t', accum_width(stage));
                    end
                    fprintf(fid, '%d\n', accum_width_final);
                    fprintf(fid, '\n====================================================\n\n');


                    %=========================================================
                    % Вывод 2:
                    %=========================================================
                    
                    % % Записываем данные для каждого каскада
                    % for stage = 1:2*N
                    %     fprintf(fid, '%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n', ...
                    %         N, R, M, Bin, Bout, stage, Bj(stage), accum_width(stage));
                    % end
                    % % Выходное усечение
                    % fprintf(fid, '%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n', ...
                    %     N, R, M, Bin, Bout, 2*N+1, Bj_final, accum_width_final);
                end
            end
        end
    end
end

warning('on', 'MATLAB:nchoosek:LargeCoefficient');

fclose(fid);
disp('Готово. Результаты записаны в CIC_pruning_table.txt');