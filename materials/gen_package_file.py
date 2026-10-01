"""
gen_pkg_file.py

The package contains:
    - Configuration parameters (N, R, M, Bin, Bout)
    - Number of stages (2N+1)
    - Arrays Bj[] and AccumWidth[] for all 2N+1 stages

Usage from command line:
    python gen_package_file.py --N 3 --R 8 --M 1 --Bin 12 --Bout 12

Usage as a module:
    from cic_pkg_file import cic_pruning, generate_sv_package
    generate_sv_package(N=3, R=8, M=1, Bin=12, Bout=12,
                        filename="pruning_pkg.sv")
"""

import argparse
import math
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
    w("// Ширина входных данных, ширина выходных данных [20:10],")
    w("// количество стадий CIC фильтра, коэффициент децимации, задержка comb-секции,")
    w("// ---------------- РЕЖИМЫ: -----------------")
    w("// Выходной разрядности, округления, нормировки,")
    w("// Hogenauer pruning, компенсации АЧХ, расширения полосы задерживания")
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
    w("    localparam bit OUTPUT_MODE        = 1'b0; // Полная/неполная выходная разрядность 1/0")
    w("    localparam bit NORMALIZE          = 1'b0; // Наличие/отсутствие нормировки 1/0")
    w("    localparam bit PRUNING_EN         = 1'b0; // наличие/отсутствие Hogenauer pruning 1/0")
    w("    localparam bit STOPBAND_EXT       = 1'b0; // наличие/отсутствие расширения полосы задерживания 1/0")
    w("")
    w("    localparam logic [1:0] ROUND_MODE = 2'd0; // режимы округления для приведения разрядности, 0 - усечение, 1 - к +inf, 2 - к нулю")
    w("    localparam bit COMP_AFR           = 1'b0; // ????????")
    w("")
    w(f"    localparam int STAGES       = {num_stages};")
    w(f"    localparam int BITS_GROWTH  = {bits_growth};")
    w(f"    localparam int FULL_WIDTH   = {full_bits};")
    w(f"    localparam int TRUNC_BITS   = {trunc_bits};")
    w("")

    # Arrays
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
def main():
    parser = argparse.ArgumentParser(
        description="Generate SystemVerilog package with CIC Hogenauer pruning parameters."
    )
    parser.add_argument("--N",    type=int, required=True, help="Number of CIC stages")
    parser.add_argument("--R",    type=int, required=True, help="Decimation factor")
    parser.add_argument("--M",    type=int, default=1,     help="Differential delay (default 1)")
    parser.add_argument("--Bin",  type=int, required=True, help="Input word width")
    parser.add_argument("--Bout", type=int, required=True, help="Output word width")
    parser.add_argument("--out",  type=str, default="cic_parameters_pkg.sv",
                        help="Output SystemVerilog file name")
    parser.add_argument("--pkg",  type=str, default="cic_parameters_pkg",
                        help="SystemVerilog package name")
    args = parser.parse_args()

    generate_sv_package(
        N=args.N, R=args.R, M=args.M, Bin=args.Bin, Bout=args.Bout,
        filename=args.out, package_name=args.pkg,
    )


if __name__ == "__main__":
    main()
