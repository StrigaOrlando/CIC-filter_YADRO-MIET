"""
gen_package_file.py

The package contains:
    - Configuration parameters (N, R, M, Bin, Bout)
    - Number of stages (2N+1)
    - Arrays Bj[] and AccumWidth[] for all 2N+1 stages

Usage from command line:
    python gen_package_file.py --N 3 --R 8 --M 1 --Bin 12 --Bout 12 --OUTPUT_MODE False --NORMALIZE False --PRUNING_EN False --STOPBAND_EXT False --ROUND_MODE 1 --COMP_AFR False

Usage as a module:
    from gen_package_file import cic_pruning, generate_sv_package
    generate_sv_package(N=3, R=8, M=1, Bin=12, Bout=12,
                        filename="pruning_pkg.sv")
"""

import argparse
import math
import sys
from math import comb
from datetime import datetime


# sqrt(C(2n, n)) for n = 1..7
_F_MANY_COMBS = [math.sqrt(comb(2 * n, n)) for n in range(1, 8)]


# ---------------------------------------------------------------------------
# Core calculation
# ---------------------------------------------------------------------------
def cic_pruning(N: int, R: int, M: int, Bin: int, Bout: int):
    """
    Compute Hogenauer accumulator pruning.

    Returns
    -------
    results     : list of (stage, Fj, minus_log2_Fj, Bj, accum_width)
    bits_growth : int
    full_bits   : int
    trunc_bits  : int
    """
    F = [0.0] * (2 * N + 1)

    # Integrators j = 1 .. N-1
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

    # Last integrator j = N
    F[N - 1] = _F_MANY_COMBS[N - 2] * math.sqrt(R * M)

    # Comb stages j = N+1 .. 2N
    for j in range(2 * N, N, -1):
        F[j - 1] = _F_MANY_COMBS[2 * N - j]

    # Final output stage j = 2N+1
    F[2 * N] = 1.0

    minus_log2_F = [-math.log2(v) for v in F]

    cic_gain     = (R * M) ** N
    bits_growth  = math.ceil(math.log2(cic_gain))
    full_bits    = bits_growth + Bin
    trunc_bits   = full_bits - Bout

    noise_var         = (2 ** trunc_bits) ** 2 / 12.0
    noise_std         = math.sqrt(noise_var)
    log2_noise_std    = math.log2(noise_std)
    half_log_6_over_N = 0.5 * math.log2(6.0 / N)

    Bj = [
        math.floor(minus_log2_F[i] + log2_noise_std + half_log_6_over_N)
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
# SystemVerilog package generator
# ---------------------------------------------------------------------------
def generate_sv_package(N: int, R: int, M: int, Bin: int, Bout: int,
                        mode1: bool = False, mode2: bool = False, mode3: bool = False,
                        mode4: bool = False, mode5: int = 0, mode6: bool = False,
                        filename: str = "cic_parameters_pkg.sv",
                        package_name: str = "cic_parameters_pkg") -> str:
    """
    Generate a SystemVerilog package with CIC pruning parameters.

    Parameters
    ----------
    N, R, M, Bin, Bout : int
        CIC filter configuration.
    filename : str
        Output file name.
    package_name : str
        Name of the SystemVerilog package.

    Returns
    -------
    str
        The full text of the generated package (also written to file).
    """
    # Keep CLI, interactive input, and module calls consistent.
    mode1, mode2, mode3, mode4, mode6 = (
        parse_bool(value) for value in (mode1, mode2, mode3, mode4, mode6)
    )
    if type(mode5) is not int or mode5 not in (0, 1, 2):
        raise ValueError("ROUND_MODE must be an integer: 0, 1, or 2")
    results, bits_growth, full_bits, trunc_bits = cic_pruning(N, R, M, Bin, Bout)

    num_stages = 2 * N + 1
    Bj_vec     = [r[3] for r in results]
    width_vec  = [r[4] for r in results]

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    lines = []
    w = lines.append

    # Header
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
    w(f"    localparam bit COMP_AFR           = 1'b{int(mode6)}; // ????????")
    w("")
    w(f"    localparam int STAGES       = {num_stages};")
    w(f"    localparam int BITS_GROWTH  = {bits_growth};")
    w(f"    localparam int FULL_WIDTH   = {full_bits};")
    w(f"    localparam int TRUNC_BITS   = {trunc_bits};")
    w("")

    if mode3:
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
# CLI
# ---------------------------------------------------------------------------

BOOL_MODES = ("OUTPUT_MODE", "NORMALIZE", "PRUNING", "STOPBAND_EXT", "COMP_AFR")
PARAMETERS = {
    "N": (3, 2, 6),
    "R": (8, 2, 8192),
    "M": (1, 1, 2),
    "Bin": (12, 2, 20),
    "Bout": (12, 2, 20),
}


def parse_bool(value):
    """Convert explicit boolean values without bool('False') surprises."""
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
    parser.add_argument("--out", default="cic_parameters_pkg.sv", help="Output file")
    parser.add_argument("--pkg", default="cic_parameters_pkg", help="SystemVerilog package name")
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
        missing_modes = any(getattr(args, name) is None
                            for name in (*BOOL_MODES, "ROUND_MODE"))
        if missing_modes and ask_mode("Configure unspecified modes?", default=False):
            for name in BOOL_MODES:
                if getattr(args, name) is None:
                    setattr(args, name, ask_mode(f"{name} (True/False)"))
            if args.ROUND_MODE is None:
                args.ROUND_MODE = ask_int("ROUND_MODE (0/1/2)", 0, 0, 2)
    for name in BOOL_MODES:
        if getattr(args, name) is None:
            setattr(args, name, False)
    if args.ROUND_MODE is None:
        args.ROUND_MODE = 0
    return args


def main():
    parser = build_parser()
    args = parser.parse_args()
    # Check explicitly supplied parameters before starting any prompts.
    for name, (_, minimum, maximum) in PARAMETERS.items():
        value = getattr(args, name)
        if value is not None and not minimum <= value <= maximum:
            parser.error(f"--{name} must be in {minimum}..{maximum}")
    args = fill_missing_interactively(args)
    print(f"N={args.N}, R={args.R}, M={args.M}, Bin={args.Bin}, Bout={args.Bout}")
    for name in (*BOOL_MODES, "ROUND_MODE"):
        print(f"{name} = {getattr(args, name)}")
    generate_sv_package(
        N=args.N, R=args.R, M=args.M, Bin=args.Bin, Bout=args.Bout,
        mode1=args.OUTPUT_MODE, mode2=args.NORMALIZE, mode3=args.PRUNING,
        mode4=args.STOPBAND_EXT, mode5=args.ROUND_MODE, mode6=args.COMP_AFR,
        filename=args.out, package_name=args.pkg,
    )


if __name__ == "__main__":
    main()
