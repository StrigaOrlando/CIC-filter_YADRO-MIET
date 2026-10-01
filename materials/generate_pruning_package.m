function generate_pruning_package(txt_filename, N, R, M, Bin, Bout, pkg_filename)
% generate_pruning_package  Создаёт Verilog-пакет с параметрами прунинга
%   generate_pruning_package('CIC_pruning_table.txt', 3, 8, 1, 12, 12, 'pruning_pkg.sv')
%
%   Входы:
%     txt_filename - путь к текстовой таблице (табуляция, заголовки)
%     N, R, M, Bin, Bout - параметры фильтра
%     pkg_filename  - имя выходного файла пакета (.sv)

    % Чтение таблицы
    data = readtable(txt_filename, 'Delimiter', '\t', 'VariableNamingRule', 'preserve');
    % Убедимся, что имена переменных совпадают с заголовками
    required_vars = {'N','R','M','Bin','Bout','Stage','Bj','AccumWidth'};
    if ~all(ismember(required_vars, data.Properties.VariableNames))
        error('Таблица не содержит всех необходимых столбцов.');
    end

    % Выбор строк под заданные параметры
    idx = data.N == N & data.R == R & data.M == M & ...
          data.Bin == Bin & data.Bout == Bout;
    selected = data(idx, :);

    if isempty(selected)
        error('Конфигурация N=%d R=%d M=%d Bin=%d Bout=%d не найдена в таблице.', ...
              N, R, M, Bin, Bout);
    end

    % Сортируем по номеру каскада
    selected = sortrows(selected, 'Stage');
    stages = selected.Stage;          % вектор номеров каскадов (1 .. 2*N+1)
    Bj_vec = selected.Bj;             % вектор Bj
    accum_vec = selected.AccumWidth;  % вектор разрядностей аккумуляторов

    num_stages = length(stages);
    expected_stages = (1:(2*N+1))';
    if ~isequal(stages, expected_stages)
        warning('Количество каскадов в таблице (%d) не совпадает с ожидаемым (%d).', ...
                num_stages, 2*N+1);
    end

    % Генерация файла пакета
    fid = fopen(pkg_filename, 'w');
    if fid == -1
        error('Не удалось открыть файл %s для записи.', pkg_filename);
    end

    fprintf(fid, 'package cic_parameters_pkg;\n\n');
    fprintf(fid, '    // Filter configuration\n');
    fprintf(fid, '    localparam int N     = %d;\n', N);
    fprintf(fid, '    localparam int R     = %d;\n', R);
    fprintf(fid, '    localparam int M     = %d;\n', M);
    fprintf(fid, '    localparam int IN_WIDTH   = %d;\n', Bin);
    fprintf(fid, '    localparam int OUT_WIDTH  = %d;\n', Bout);
    fprintf(fid, '    localparam int CIC_STAGES = %d;  // 2*N+1\n\n', 2*N+1);

    % Gain и Full_width
    fprintf(fid, "    localparam GAIN = %d;\n", (R*M)^N);
    fprintf(fid, "    localparam FULL_WIDTH = %d;\n\n", Bin + log2((R*M)^N));
    
    % Массив Bj (индексы от 1)
    fprintf(fid, '    // Bj: number of LSBs truncated at each stage input\n');
    fprintf(fid, '    localparam int Bj [%d:0] = {', num_stages-1);
    for i = 1:num_stages
        if i > 1
            fprintf(fid, ', ');
        end
        fprintf(fid, '%d', Bj_vec(i));
    end
    fprintf(fid, '};\n\n');

    % Массив AccumWidth
    fprintf(fid, '    // AccumWidth: required accumulator bit width\n');
    fprintf(fid, '    localparam int AccumWidth [%d:0] = {', num_stages-1);
    for i = 1:num_stages
        if i > 1
            fprintf(fid, ', ');
        end
        fprintf(fid, '%d', accum_vec(i));
    end
    fprintf(fid, '};\n\n');

    % Режимы:
    fprintf(fid, "    localparam bit OUTPUT_MODE    = 1'b0;\n");
    fprintf(fid, "    localparam bit NORMALIZE      = 1'b0;\n");
    fprintf(fid, "    localparam bit PRUNING_EN     = 1'b0;\n");
    fprintf(fid, "    localparam bit STOPBAND_EXT   = 1'b0;\n\n");

    fprintf(fid, "    localparam bit ROUNDE_MODE    = 1'b0;\n");
    fprintf(fid, "    localparam bit COMP_AFR       = 1'b0;\n\n");


    fprintf(fid, 'endpackage\n');
    fclose(fid);

    fprintf('Пакет успешно создан: %s\n', pkg_filename);
end