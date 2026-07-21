function write_vector_txt(filename, v)
% WRITE_VECTOR_TXT Запись целочисленного вектора в текстовый файл.
%
% Формат файла:
%   одно число в одной строке.
%
% Такой формат удобно читать в testbench через fscanf.

    fid = fopen(filename, 'w');

    if fid < 0
        error("Не удалось открыть файл: %s", filename);
    end

    cleanup = onCleanup(@() fclose(fid));

    for i = 1:length(v)
        fprintf(fid, '%d\n', v(i));
    end
end