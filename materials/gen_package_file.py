"""
gen_package_file.py

Пакет содержит:
    - Параметры конфигурации (N, R, M, Bin, Bout)
    - Количество каскадов (2N+1)
    - Массивы Bj[] и AccumWidth[] для всех 2N+1 каскадов
    - Коэффициенты КИХ-компенсатора, рассчитанные по алгоритму из ciccomp.m
    - Параметры нормировки, полученные вызовом исходной csd_divider.m в MATLAB

Запуск из командной строки:
    python gen_package_file.py --N 3 --R 8 --M 1 --Bin 12 --Bout 12
    python gen_package_file.py --N 3 --R 32 --M 1 --Bin 12 --Bout 12 --COMP_L 5 --COMP_B 12 --COMP_WP_PI 0.5

Для генерации при включённой нормировке требуется установленный MATLAB. Файл csd_divider.m разместите
рядом с этим скриптом либо укажите --csd-file. Если MATLAB не найден автоматически,
укажите --matlab-exe. Дополнительные пакеты Python не требуются.

Для нормировки S = S_prune + S_pre, где S_prune = Bj[2*N] при включённом прунинге, иначе S_prune = 0.
S_pre это количество младших разрядов, дополнительно отбрасываемых согласно PRE_NORM_WIDTH.
В MATLAB передаётся D = (R*M)^N / 2^S: функция представляет обратную величину 1/D.
NORM_CSD_SHIFT содержит powers с прибавлением fracBits:
1/D ~= sum((-1)^NORM_CSD_NEGATIVE[j] * 2^NORM_CSD_SHIFT[j]) / 2^NORM_FRAC_BITS.
Четыре параметра выводятся независимо от флага NORMALIZE.

Использование в качестве модуля:
    from gen_package_file import cic_pruning, generate_sv_package
    generate_sv_package(N=3, R=8, M=1, Bin=12, Bout=12,
                        filename="pruning_pkg.sv")
"""

import argparse
import math
import sys
import json
import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path
from math import comb
from datetime import datetime
from itertools import product


# Значения sqrt(C(2n, n)) для n = 1..7
_F_MANY_COMBS = [math.sqrt(comb(2 * n, n)) for n in range(1, 8)]


# ---------------------------------------------------------------------------
# Основной расчёт
# ---------------------------------------------------------------------------
def cic_pruning(N: int, R: int, M: int, Bin: int, Bout: int):
    """
    Расчёт сокращения разрядности накопителей по методу Хогенауэра.

    Возвращаемые значения
    --------------------
    results     : (stage, Fj, minus_log2_Fj, Bj, accum_width)
    bits_growth : int
    full_bits   : int
    trunc_bits  : int
    """
    F = [0.0] * (2 * N + 1)

    # Интеграторы j = 1 .. N-1
    for j in range(N - 1, 0, -1):
        length = (R * M - 1) * N + j
        h = [0] * length
        for k in range(length):
            s = 0
            for L in range(k // (R * M) + 1):
                s += ((-1) ** L) * comb(N, L) \
                     * comb(N - j + k - R * M * L, k - R * M * L)
            h[k] = s
        F[j - 1] = math.sqrt(sum(v * v for v in h))

    # Последний интегратор j = N
    F[N - 1] = _F_MANY_COMBS[N - 2] * math.sqrt(R * M)

    # Каскады гребенчатой секции j = N+1 .. 2N
    for j in range(2 * N, N, -1):
        F[j - 1] = _F_MANY_COMBS[2 * N - j]

    # Конечный выходной каскад j = 2N+1
    F[2 * N] = 1.0

    minus_log2_F = [-math.log2(v) for v in F]

    cic_gain     = (R * M) ** N
    bits_growth  = math.ceil(math.log2(cic_gain))
    full_bits    = bits_growth + Bin
    trunc_bits = max(0, full_bits - Bout)

    noise_var         = (2 ** trunc_bits) ** 2 / 12.0
    noise_std         = math.sqrt(noise_var)
    log2_noise_std    = math.log2(noise_std)
    half_log_6_over_N = 0.5 * math.log2(6.0 / N)

    Bj = [
    max(0, math.floor(minus_log2_F[i] + log2_noise_std + half_log_6_over_N))
    for i in range(2 * N)
    ]

    results = []
    for stage in range(1, 2 * N + 1):
        idx = stage - 1
        accum_width = full_bits - Bj[idx]
        results.append((stage, F[idx], minus_log2_F[idx], Bj[idx], accum_width))

    results.append((2 * N + 1, 1.0, 0.0, trunc_bits, Bout))

    return results, bits_growth, full_bits, trunc_bits


# ---------------------------------------------------------------------------
# КИХ-компенсатор (перенос алгоритма из ciccomp.m)
# ---------------------------------------------------------------------------
def ciccomp(N: int, R: int, L: int = 5, B: int = 12,
            wp: float = math.pi / 2, M: int = 1):
    """
    Возвращает уникальные коэффициенты: центральный, затем по одному от каждой пары.
    """
    if any(type(value) is not int or value < 1 for value in (N, R, M, B)):
        raise ValueError("N, R, M and COMP_B must be positive integers")
    if type(L) is not int or L not in (3, 5, 7):
        raise ValueError("COMP_L must be 3, 5 or 7")
    if not math.isfinite(wp) or not 0 < wp <= math.pi:
        raise ValueError("wp must be finite and in (0, pi]")

    K = 64
    w = [wp * k / (K - 1) for k in range(K)]
    HC = [1.0] + [
        (1 / (R * M) * math.sin(M * omega / 2)
         / math.sin(omega / (2 * R))) ** N for omega in w[1:]
    ]
    HH = [[1.0] + [2 * math.cos(omega * p) for p in range(1, (L + 1) // 2)]
          for omega in w]
    ck = [-(2 ** k) for k in range(B)] + [0] + [2 ** k for k in range(B)]
    epsi_min = math.inf
    c_kappa = None

    for center in ck[B + 1:]:
        for tail in product(ck, repeat=(L - 1) // 2):
            candidate = (center,) + tail
            H0 = center + 2 * sum(tail)
            if H0 == 0:
                continue
            # На нулевой частоте HC * H / H0 = 1.0.
            low = high = 1.0
            for hc, row in zip(HC[1:], HH[1:]):
                H = float(center)
                for p, tap in enumerate(tail, 1):
                    H += row[p] * tap
                value = hc * H / H0
                low = min(low, value)
                high = max(high, value)
                # Размах значений не может уменьшиться при добавлении новых точек.
                # Досрочное завершение не исключает наборы, способные улучшить результат.
                if high - low >= epsi_min:
                    break
            else:
                epsi_min = high - low
                c_kappa = candidate

    dc_gain = c_kappa[0] + 2 * sum(c_kappa[1:])
    exponent = min(range(-B, B + 1),
                   key=lambda k: abs(1 / (2.0 ** k * dc_gain) - 1))
    return [math.ldexp(float(tap), exponent) for tap in c_kappa]


def compensation_parameters(N: int, R: int, L: int = 5, B: int = 12,
                            wp: float = math.pi / 2, M: int = 1):
    """
    Возвращает число дробных бит, четыре целых коэффициента со знаком и число защитных бит.

    Коэффициенты в виде степеней двойки имеют точное двоичное представление.
    Выбирается минимальное неотрицательное число дробных бит, достаточное для
    точного представления каждого коэффициента; нулевые коэффициенты не учитываются.
    Неиспользуемые элементы дополняются нулями. При расчёте защитных бит
    учитываются оба коэффициента каждой симметричной пары.
    """
    coefficients = ciccomp(N, R, L, B, wp, M)
    ratios = [value.as_integer_ratio() for value in coefficients]
    fractional_bits = max(denominator.bit_length() - 1 for _, denominator in ratios)
    coefficient_q = [numerator * ((1 << fractional_bits) // denominator)
                     for numerator, denominator in ratios]
    if any(not -(1 << 31) <= value < (1 << 31) for value in coefficient_q):
        raise ValueError("COMP_COEFF_Q does not fit SystemVerilog int signed (32 bits)")
    magnitude_sum_q = abs(coefficient_q[0]) + 2 * sum(abs(v) for v in coefficient_q[1:])
    # Точное значение max(0, ceil(log2(sum(abs(h))))), без ошибок округления вблизи степеней двойки.
    growth = max(0, (magnitude_sum_q - 1).bit_length() - fractional_bits)
    coefficient_q += [0] * (4 - len(coefficient_q))
    return fractional_bits, coefficient_q, growth


# ---------------------------------------------------------------------------
# Вызов исходной MATLAB-функции нормировки
# ---------------------------------------------------------------------------
def matlab_csd_divider(divisor, matlab_exe=None, csd_file=None):
    """Вызывает csd_divider(D) в MATLAB и возвращает её структуру через JSON.

    Второй аргумент не передаётся: используется точность из исходного .m-файла.
    Вычисление CSD выполняется исключительно в MATLAB.
    """
    if not math.isfinite(divisor) or divisor <= 0:
        raise ValueError("Делитель для csd_divider должен быть конечным и положительным.")
    source = Path(csd_file) if csd_file else Path(__file__).with_name("csd_divider.m")
    source = source.resolve()
    if not source.is_file() or source.name != "csd_divider.m":
        raise ValueError(f"Не найден файл csd_divider.m: {source}")

    # Явный путь имеет приоритет, затем используются переменная среды и PATH.
    executable = matlab_exe or os.environ.get("MATLAB_EXE") or shutil.which("matlab")
    if executable is None and os.name == "nt":
        root = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "MATLAB"
        candidates = [root / "bin" / "matlab.exe"]
        candidates += sorted(root.glob("R*/bin/matlab.exe"), reverse=True)
        executable = next((str(path) for path in candidates if path.is_file()), None)
    if executable is None:
        raise RuntimeError("MATLAB не найден. Укажите --matlab-exe с путём к MATLAB.")

    temporary = Path(tempfile.gettempdir()) / ("cic_csd_" + uuid.uuid4().hex)
    temporary.mkdir()
    try:
        request = {"divisor": divisor, "sourceDir": str(source.parent),
                   "outputFile": str(temporary / "result.json")}
        (temporary / "request.json").write_text(json.dumps(request), encoding="utf-8")
        # run() выполняет сценарий в его каталоге; пути передаются как данные JSON.
        script = temporary / "call_csd.m"
        script.write_text(
            "request = jsondecode(fileread('request.json'));\n"
            "addpath(request.sourceDir, '-begin');\n"
            "c = csd_divider(request.divisor);\n"
            "fid = fopen(request.outputFile, 'w', 'n', 'UTF-8');\n"
            "assert(fid ~= -1, 'Cannot create MATLAB result file');\n"
            "cleanup = onCleanup(@() fclose(fid));\n"
            "fprintf(fid, '%s', jsonencode(c));\n"
            "clear cleanup;\n", encoding="utf-8")
        statement = "run('" + script.as_posix().replace("'", "''") + "')"
        command = [str(executable)]
        if os.name == "nt":
            command.append("-wait")
        command += ["-batch", statement]
        try:
            completed = subprocess.run(
                command, capture_output=True, text=True, encoding="utf-8", errors="replace",
                timeout=300, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        except OSError as exc:
            raise RuntimeError(f"Не удалось запустить MATLAB: {executable}") from exc
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError("MATLAB не завершил расчёт за 300 секунд.") from exc
        if completed.returncode:
            raise RuntimeError("Ошибка MATLAB при вызове csd_divider:\n" +
                               completed.stdout + completed.stderr)
        output = temporary / "result.json"
        if not output.is_file():
            raise RuntimeError("MATLAB не создал файл результата csd_divider.")
        result = json.loads(output.read_text(encoding="utf-8-sig"))
    finally:
        # Удаляем только собственные временные файлы в созданном для вызова каталоге.
        for name in ("request.json", "call_csd.m", "result.json"):
            (temporary / name).unlink(missing_ok=True)
        temporary.rmdir()

    # MATLAB кодирует вектор из одного элемента как число: приводим его к списку.
    def integer(value, name):
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or int(value) != value:
            raise ValueError(f"Некорректное целое поле MATLAB: {name}")
        return int(value)

    frac_bits = integer(result["fracBits"], "fracBits")
    count = integer(result["numTerms"], "numTerms")
    powers = result["powers"] if isinstance(result["powers"], list) else [result["powers"]]
    signs = result["signs"] if isinstance(result["signs"], list) else [result["signs"]]
    powers = [integer(value, "powers") for value in powers]
    signs = [integer(value, "signs") for value in signs]
    if frac_bits < 0 or count < 1 or len(powers) != count or len(signs) != count or any(v not in (0, 1) for v in signs):
        raise ValueError("Несогласованные поля результата csd_divider.")
    return {"fracBits": frac_bits, "numTerms": count, "powers": powers, "signs": signs}


# ---------------------------------------------------------------------------
# Генератор пакета SystemVerilog
# ---------------------------------------------------------------------------
def generate_sv_package(N: int, R: int, M: int, Bin: int, Bout: int,
                        mode1: bool = False, mode2: bool = False, mode3: bool = False,
                        mode4: bool = False, mode5: int = 0, mode6: bool = False,
                        filename: str = "cic_parameters_pkg.sv",
                        package_name: str = "cic_parameters_pkg",
                        NUM_CHANNELS: int = 4, CHANNEL_FIFO_DEPTH: int = 16,
                        LOAD_AWARE_ARB: int = 1, ARB_AGE_LIMIT: int = 32,
                        ARB_HIGH_WATERMARK: int = 12,
                        COMP_L: int = 5, COMP_B: int = 12,
                        COMP_WP_PI: float = 0.5,
                        matlab_exe=None, csd_file=None, PRE_NORM_WIDTH: int = 0) -> str:
    """
    Формирует пакет SystemVerilog с параметрами сокращения разрядности CIC-фильтра.

    Параметры
    ---------
    N, R, M, Bin, Bout : int
        Конфигурация CIC-фильтра.
    filename : str
        Имя выходного файла.
    package_name : str
        Имя пакета SystemVerilog.
    NUM_CHANNELS, CHANNEL_FIFO_DEPTH : int
        Количество каналов и глубина FIFO; оба значения >= 1.
    LOAD_AWARE_ARB : int
        Режим арбитра: 0 — простой, 1 — с учётом загрузки.
    ARB_AGE_LIMIT : int
        Неотрицательный порог времени ожидания для повышения приоритета.
    ARB_HIGH_WATERMARK : int
        Порог заполнения FIFO для повышения приоритета: от 1 до CHANNEL_FIFO_DEPTH.
    COMP_L : int
        Полная длина симметричного КИХ-фильтра: 3, 5 или 7 (по умолчанию 5).
    COMP_B : int
        Количество перебираемых показателей степени B из ciccomp.m (по умолчанию 12).
    COMP_WP_PI : float
        Граница полосы пропускания wp / pi (по умолчанию 0.5, то есть pi/2).
    matlab_exe, csd_file : str или None
        Путь к MATLAB и к исходной функции csd_divider.m.
        По умолчанию MATLAB ищется автоматически, .m-файл — рядом с генератором.

    Возвращаемое значение
    --------------------
    str
        Полный текст сформированного пакета, который также записывается в файл.
    """
    # Единая обработка режимов для командной строки, интерактивного ввода и вызовов из модуля.
    mode1, mode2, mode3, mode4, mode6 = (
        parse_bool(value) for value in (mode1, mode2, mode3, mode4, mode6)
    )
    if type(mode5) is not int or mode5 not in (0, 1, 2):
        raise ValueError("ROUND_MODE must be an integer: 0, 1, or 2")
    validate_channel_parameters(NUM_CHANNELS, CHANNEL_FIFO_DEPTH, LOAD_AWARE_ARB,
                                ARB_AGE_LIMIT, ARB_HIGH_WATERMARK)
    COMP_COEFF_FRAC_BITS, COMP_COEFF_Q, COMP_GROWTH_W = compensation_parameters(
        N, R, COMP_L, COMP_B, COMP_WP_PI * math.pi, M
    )
    results, bits_growth, full_bits, trunc_bits = cic_pruning(N, R, M, Bin, Bout)

    num_stages = 2 * N + 1
    Bj_vec     = [r[3] for r in results]
    width_vec  = [r[4] for r in results]
    # Требуемая ширина после последнего comb и перед нормировкой.
    pre_norm_width = PRE_NORM_WIDTH
    if type(pre_norm_width) is not int or pre_norm_width < 0:
        raise ValueError("PRE_NORM_WIDTH must be a nonnegative integer")

    # Предпоследний элемент соответствует Bj[2*N] в пакете SystemVerilog.
    s_prune = Bj_vec[-2] if mode3 else 0
    comb_width = full_bits - s_prune
    if mode2 and pre_norm_width > comb_width:
        raise ValueError(f"PRE_NORM_WIDTH must be <= {comb_width}")
    
    # Показатель S для нормировки учитывает pruning и PRE_NORM_WIDTH.
    s_pre = max(0, comb_width - pre_norm_width) if mode2 and pre_norm_width > 0 else 0
    norm_scale = s_prune + s_pre
    
    # Передаём делитель D: MATLAB возвращает CSD-представление 1/D.
    cic_gain = (R * M) ** N
    norm_divisor = cic_gain / (2.0 ** norm_scale)
    norm = matlab_csd_divider(norm_divisor, matlab_exe, csd_file) if mode2 else {
        "fracBits": 0, "numTerms": 1, "powers": [0], "signs": [0]}

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    lines = []
    w = lines.append

    # Заголовок
    w("// ============================================================================")
    w("// В данном файле package есть ")
    w("// Hogenauer accumulator pruning technique")
    w("// --------------- ПАРАМЕТРЫ: ---------------")
    w("// Ширина входных данных, ширина выходных данных [10:20],")
    w("// количество стадий CIC фильтра, коэффициент децимации, задержка comb-секции,")
    w("// ---------------- РЕЖИМЫ: -----------------")
    w("// Выходной разрядности, округления, нормировки,")
    w("// Hogenauer pruning, компенсации АЧХ, расширения полосы задерживания")
    w("// ---------------- ФУНКЦИИ: ----------------")
    w("// Коэффициент усиления CIC, прирост разрядности,")
    w("// полная внутренняя/выходная разрядность, ")
    w("// количество бит, отбрасываемых при неполной выходной разрядности")
    w("// ============================================================================")
    w("")
    w(f"package {package_name};")
    w("")
    w(f"    localparam IN_WIDTH      = {Bin};")
    w(f"    localparam OUT_WIDTH     = {Bout};")
    w(f"    localparam N             = {N}; // Количество стадий CIC фильтра (от 2 до 6)")
    w(f"    localparam M             = {M}; // Задержка comb-секции (1 или 2)")
    w(f"    localparam R             = {R}; // Коэффициент децимации R ≤ 700")
    w("")
    w(f"    localparam bit OUTPUT_MODE        = 1'b{int(mode1)}; // Полная/неполная выходная разрядность 1/0")
    w(f"    localparam bit NORMALIZE          = 1'b{int(mode2)}; // Наличие/отсутствие нормировки 1/0")
    w(f"    localparam bit PRUNING_EN         = 1'b{int(mode3)}; // наличие/отсутствие Hogenauer pruning 1/0")
    w(f"    localparam bit STOPBAND_EXT       = 1'b{int(mode4)}; // наличие/отсутствие расширения полосы задерживания 1/0")
    w("")
    w(f"    localparam logic [1:0] ROUND_MODE = 2'd{mode5}; // режимы округления для приведения разрядности, 0 - усечение, 1 - к +inf, 2 - к нулю")
    w(f"    localparam bit COMP_AFR           = 1'b{int(mode6)}; // наличие/отсутствие КИХ-компенсации АЧХ 1/0")
    w("")
    w(f"    localparam int PRE_NORM_WIDTH = {pre_norm_width}; // наличие/отсутствие предварительного уменьшения разрядности перед нормировкой, 0 - выключено, иначе требуемая ширина после последнего comb и перед нормировкой")
    w("")
    w("    // Параметры многоканальной обработки")
    w(f"    localparam int NUM_CHANNELS       = {NUM_CHANNELS}; // Количество независимых логических потоков")
    w(f"    localparam int CHANNEL_FIFO_DEPTH = {CHANNEL_FIFO_DEPTH}; // Глубина входной FIFO каждого канала")
    w(f"    localparam bit LOAD_AWARE_ARB     = 1'b{LOAD_AWARE_ARB}; // сложность арбитра, 0 - простой(с0-с1-с2-с3-с0...), 1 - сложный")
    w(f"    localparam int ARB_AGE_LIMIT      = {ARB_AGE_LIMIT}; // После этого времени ожидания канал получает приоритет")
    w(f"    localparam int ARB_HIGH_WATERMARK = {ARB_HIGH_WATERMARK}; // При достижении уровня учитывается максимальная заполненность FIFO")
    w("")
    w("    // Параметры КИХ-компенсатора")
    w(f"    localparam int COMP_L               = {COMP_L}; // Количество коэффициентов (отсчётов) КИХ-компенсатора, нечётное: 3, 5 или 7")
    w(f"    localparam int COMP_COEFF_FRAC_BITS = {COMP_COEFF_FRAC_BITS}; // Количество дробных бит для представления коэффициентов КИХ-компенсатора")
    coeff_str = ", ".join(str(value) for value in COMP_COEFF_Q)
    w(f"    localparam int signed COMP_COEFF_Q [0:3] = '{{{coeff_str}}}; // Коэффициенты КИХ, умноженные на 2^COMP_COEFF_FRAC_BITS")
    w("")
    w("    // Дополнительный рост выходной разрядности КИХ-компенсатора")
    w(f"    localparam int COMP_GROWTH_W = {COMP_GROWTH_W}; // Количество дополнительных старших guard-бит для предотвращения переполнения в КИХ")
    w("")
    w(f"    localparam int STAGES       = {num_stages};")
    w(f"    localparam int BITS_GROWTH  = {bits_growth};")
    w(f"    localparam int FULL_WIDTH   = {full_bits};")
    w(f"    localparam int TRUNC_BITS   = {trunc_bits};")
    w("")

    w("    // -----------------------------------------------------------")
    w("    //   Bj[j]          - количество бит усекаемых на каждом каскаде j")
    w("    //   AccumWidth[j]  - оставшееся кол-во бит на каскаде j")
    w("    // -----------------------------------------------------------")
    bj_str    = ", ".join(str(v) for v in Bj_vec)
    width_str = ", ".join(str(v) for v in width_vec)
    w(f"    localparam int Bj         [1:{num_stages}] = '{{{bj_str}}};")
    w(f"    localparam int AccumWidth [1:{num_stages}] = '{{{width_str}}};")
    w("")

    w("")
    w("    // Параметры нормировки")
    w(f"    localparam int NORM_FRAC_BITS = {norm['fracBits']}; // Параметр F, позволяет задавать точность представления, в дальнейшем на него делается поправка")
    w(f"    localparam int NORM_CSD_TERM_COUNT = {norm['numTerms']}; // Количество коэффициентов в CSD")
    shifts_str = ", ".join(str(value + norm["fracBits"]) for value in norm["powers"])
    signs_str = ", ".join(str(value) for value in norm["signs"])
    w(f"    localparam int NORM_CSD_SHIFT [0:NORM_CSD_TERM_COUNT-1] = '{{{shifts_str}}}; // Коэффициенты CSD")
    w(f"    localparam bit NORM_CSD_NEGATIVE [0:NORM_CSD_TERM_COUNT-1] = '{{{signs_str}}}; // Знаки при слагаемых в CSD, 0 - \"+\", 1 - \"-\"")
    w("")
    w("endpackage")

    text = "\n".join(lines) + "\n"

    with open(filename, "w", encoding="utf-8") as f:
        f.write(text)

    print(f"[OK] SystemVerilog package written to: {filename}")
    print(f"     Configuration: N={N}, R={R}, M={M}, Bin={Bin}, Bout={Bout}")
    print(f"     Stages: {num_stages}, full width: {full_bits}, "
          f"truncated output bits: {trunc_bits}")
    return text


# ---------------------------------------------------------------------------
# Интерфейс командной строки
# ---------------------------------------------------------------------------

BOOL_MODES = ("OUTPUT_MODE", "NORMALIZE", "PRUNING", "STOPBAND_EXT", "COMP_AFR")
PARAMETERS = {
    "N": (3, 2, 6),
    "R": (8, 2, 700),
    "M": (1, 1, 2),
    "Bin": (12, 2, 20),
    "Bout": (12, 2, 20),
}
CHANNEL_PARAMETERS = {
    "NUM_CHANNELS": (4, 1, None),
    "CHANNEL_FIFO_DEPTH": (16, 1, None),
    "LOAD_AWARE_ARB": (1, 0, 1),
    "ARB_AGE_LIMIT": (32, 0, None),
    "ARB_HIGH_WATERMARK": (12, 1, None),
}


def validate_channel_parameters(NUM_CHANNELS, CHANNEL_FIFO_DEPTH, LOAD_AWARE_ARB,
                                ARB_AGE_LIMIT, ARB_HIGH_WATERMARK):
    values = locals()
    for name, (_, minimum, maximum) in CHANNEL_PARAMETERS.items():
        value = values[name]
        if type(value) is not int or value < minimum or (maximum is not None and value > maximum):
            raise ValueError(f"{name} must be an integer >= {minimum}" +
                             (f" and <= {maximum}" if maximum is not None else ""))
    if ARB_HIGH_WATERMARK > CHANNEL_FIFO_DEPTH:
        raise ValueError("ARB_HIGH_WATERMARK must be in 1..CHANNEL_FIFO_DEPTH")


def parse_bool(value):
    """Преобразует логические значения без ошибки, при которой bool('False') даёт True."""
    if isinstance(value, bool):
        return value
    raw = str(value).strip().lower()
    if raw in ("true", "t", "1", "yes", "y"):
        return True
    if raw in ("false", "f", "0", "no", "n"):
        return False
    raise argparse.ArgumentTypeError("Expected True/False, 1/0, or yes/no")


def build_parser():
    parser = argparse.ArgumentParser(
        description="Generate SystemVerilog package with CIC Hogenauer pruning parameters."
    )
    for name, (default, minimum, maximum) in PARAMETERS.items():
        parser.add_argument(f"--{name}", type=int, default=None,
                            help=f"Range: {minimum}..{maximum}; interactive default: {default}")
    for name in BOOL_MODES:
        flags = [f"--{name}"]
        if name == "PRUNING":
            flags.append("--PRUNING_EN")
        parser.add_argument(*flags, type=parse_bool, nargs="?", const=True,
                            default=None, metavar="True|False",
                            help="Default: False; a flag without a value enables the mode")
    parser.add_argument("--ROUND_MODE", type=int, choices=(0, 1, 2), default=None,
                        help="0: truncate; 1: toward +inf; 2: toward zero (default: 0)")
    parser.add_argument("--PRE_NORM_WIDTH", type=int, default=None,
                        help="Target width before normalization in bits (0 = off)")
    for name, (default, minimum, maximum) in CHANNEL_PARAMETERS.items():
        parser.add_argument(f"--{name}", type=int, default=None,
                            help=f"Default: {default}; minimum: {minimum}" +
                            (f"; maximum: {maximum}" if maximum is not None else "") +
                            ("; maximum: CHANNEL_FIFO_DEPTH" if name == "ARB_HIGH_WATERMARK" else ""))
    parser.add_argument("--out", default="cic_parameters_pkg.sv", help="Output file")
    parser.add_argument("--COMP_L", type=int, choices=(3, 5, 7), default=None,
                        help="Full FIR length (default: 5)")
    parser.add_argument("--COMP_B", type=int, default=None,
                        help="Search exponent count B from ciccomp.m (default: 12); search grows as (2*B+1)^((L+1)/2)")
    parser.add_argument("--COMP_WP_PI", type=float, default=None,
                        help="Passband edge as a fraction of pi, in (0, 1]; default: 0.5 (pi/2)")
    parser.add_argument("--pkg", default="cic_parameters_pkg", help="SystemVerilog package name")
    parser.add_argument("--matlab-exe", default=None, help="Path to the MATLAB executable (optional; detected automatically by default)")
    parser.add_argument("--csd-file", default=None, help="Path to csd_divider.m (default: next to the generator script)")
    parser.add_argument("--interactive", action="store_true",
                        help="Prompt for missing parameters and modes")
    return parser


def ask_int(prompt, default=None, min_val=None, max_val=None):
    suffix = f" [{default}]" if default is not None else ""
    while True:
        raw = input(f"{prompt}{suffix}: ").strip()
        try:
            value = default if raw == "" and default is not None else int(raw)
        except ValueError:
            print("Please enter an integer.")
            continue
        if min_val is not None and value < min_val:
            print(f"Value must be >= {min_val}.")
            continue
        if max_val is not None and value > max_val:
            print(f"Value must be <= {max_val}.")
            continue
        return value


def ask_mode(prompt, default=False):
    while True:
        raw = input(f"{prompt} [{default}]: ").strip()
        if raw == "":
            return parse_bool(default)
        try:
            return parse_bool(raw)
        except argparse.ArgumentTypeError as exc:
            print(exc)


def fill_missing_interactively(args):
    needs_prompt = args.interactive or any(
        getattr(args, name) is None for name in PARAMETERS
    )
    if needs_prompt:
        print("=== CIC pruning package generator ===")
        print("Press Enter to accept the default value in brackets.")
        for name, (default, minimum, maximum) in PARAMETERS.items():
            if getattr(args, name) is None:
                setattr(args, name, ask_int(name, default, minimum, maximum))
        if args.COMP_L is None:
            while True:
                args.COMP_L = ask_int("COMP_L (3/5/7)", 5, 3, 7)
                if args.COMP_L in (3, 5, 7):
                    break
                print("COMP_L must be 3, 5 or 7.")
        if args.COMP_B is None:
            args.COMP_B = ask_int("COMP_B (search exponent count)", 12, 1)
        if args.COMP_WP_PI is None:
            while True:
                raw = input("COMP_WP_PI (wp/pi) [0.5]: ").strip()
                try:
                    value = float(raw) if raw else 0.5
                except ValueError:
                    print("Enter a number in (0, 1].")
                    continue
                if math.isfinite(value) and 0 < value <= 1:
                    args.COMP_WP_PI = value
                    break
                print("Enter a number in (0, 1].")
        missing_modes = any(getattr(args, name) is None
                            for name in (*BOOL_MODES, "ROUND_MODE"))
        if missing_modes and ask_mode("Configure unspecified modes?", default=False):
            for name in BOOL_MODES:
                if getattr(args, name) is None:
                    setattr(args, name, ask_mode(f"{name} (True/False)"))
            if args.ROUND_MODE is None:
                args.ROUND_MODE = ask_int("ROUND_MODE (0/1/2)", 0, 0, 2)
        if args.PRE_NORM_WIDTH is None:
            args.PRE_NORM_WIDTH = ask_int("PRE_NORM_WIDTH (bits, 0 = off)", 0, 0)   
        for name, (default, minimum, maximum) in CHANNEL_PARAMETERS.items():
            if getattr(args, name) is None:
                if name == "ARB_HIGH_WATERMARK":
                    maximum = args.CHANNEL_FIFO_DEPTH
                    default = min(default, maximum)
                setattr(args, name, ask_int(name, default, minimum, maximum))
    for name, (default, _, _) in CHANNEL_PARAMETERS.items():
        if getattr(args, name) is None:
            setattr(args, name, default)
    for name in BOOL_MODES:
        if getattr(args, name) is None:
            setattr(args, name, False)
    if args.ROUND_MODE is None:
        args.ROUND_MODE = 0
    if args.COMP_L is None:
        args.COMP_L = 5
    if args.COMP_B is None:
        args.COMP_B = 12
    if args.COMP_WP_PI is None:
        args.COMP_WP_PI = 0.5
    if args.PRE_NORM_WIDTH is None:
        args.PRE_NORM_WIDTH = 0
    return args


def main():
    parser = build_parser()
    args = parser.parse_args()
    # Проверяем явно заданные параметры до начала интерактивного ввода.
    for name, (_, minimum, maximum) in PARAMETERS.items():
        value = getattr(args, name)
        if value is not None and not minimum <= value <= maximum:
            parser.error(f"--{name} must be in {minimum}..{maximum}")
    for name, (_, minimum, maximum) in CHANNEL_PARAMETERS.items():
        value = getattr(args, name)
        if value is not None and (value < minimum or (maximum is not None and value > maximum)):
            parser.error(f"--{name} must be >= {minimum}" +
                         (f" and <= {maximum}" if maximum is not None else ""))
    if args.COMP_B is not None and args.COMP_B < 1:
        parser.error("--COMP_B must be >= 1")
    if args.COMP_WP_PI is not None and (not math.isfinite(args.COMP_WP_PI) or not 0 < args.COMP_WP_PI <= 1):
        parser.error("--COMP_WP_PI must be finite and in (0, 1]")
    args = fill_missing_interactively(args)
    try:
        validate_channel_parameters(**{name: getattr(args, name) for name in CHANNEL_PARAMETERS})
    except ValueError as exc:
        parser.error(str(exc))
    print(f"N={args.N}, R={args.R}, M={args.M}, Bin={args.Bin}, Bout={args.Bout}")
    for name in (*BOOL_MODES, "ROUND_MODE"):
        print(f"{name} = {getattr(args, name)}")
    for name in CHANNEL_PARAMETERS:
        print(f"{name} = {getattr(args, name)}")
    print(f"COMP_L={args.COMP_L}, COMP_B={args.COMP_B}, COMP_WP_PI={args.COMP_WP_PI}")
    print("Calculating FIR compensation and MATLAB normalization parameters...")
    try:
        generate_sv_package(
            N=args.N, R=args.R, M=args.M, Bin=args.Bin, Bout=args.Bout,
            mode1=args.OUTPUT_MODE, mode2=args.NORMALIZE, mode3=args.PRUNING,
            mode4=args.STOPBAND_EXT, mode5=args.ROUND_MODE, mode6=args.COMP_AFR,
            filename=args.out, package_name=args.pkg,
            NUM_CHANNELS=args.NUM_CHANNELS, CHANNEL_FIFO_DEPTH=args.CHANNEL_FIFO_DEPTH,
            LOAD_AWARE_ARB=args.LOAD_AWARE_ARB, ARB_AGE_LIMIT=args.ARB_AGE_LIMIT,
            ARB_HIGH_WATERMARK=args.ARB_HIGH_WATERMARK,
            COMP_L=args.COMP_L, COMP_B=args.COMP_B, COMP_WP_PI=args.COMP_WP_PI,
            matlab_exe=args.matlab_exe, csd_file=args.csd_file,
            PRE_NORM_WIDTH=args.PRE_NORM_WIDTH,
        )
    except (RuntimeError, ValueError, OSError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
