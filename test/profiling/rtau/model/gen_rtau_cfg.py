# AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-09.
"""
gen_rtau_cfg.py -- bit-exact model, tables and test vectors for the 1/tau LUT in the
team's 8 configurations (2026-11-09):

    word size W   : 18 or 32 bits     -- EVERY number uses the same signed format
    samples NB    : 128 or 256 per curve (pieces over -64 .. +64 mV)
    memory        : block RAM or distributed RAM  (same table and same math; only the
                    Verilog RAM style changes, so the model does not care)

One format for every number (V in mV, offset b, slope dy, output y):
    W = 18 : Q10.7   (1 sign + 10 integer + 7 fraction bits)   F = 7
    W = 32 : Q10.21  (1 sign + 10 integer + 21 fraction bits)  F = 21
    10 integer bits because 1/tau reaches 940 1/s.

Bit slicing (F = fraction bits, K = log2(NB)):
    u     = V + 64 mV = V + 2^(F+6), clamped to 0 .. 2^(F+7)-1   (F+7 bits)
    index = u[F+6 : F+7-K]         (K bits: which piece)
    frac  = u[F+6-K : 0]           (FW = F+7-K bits: position inside the piece)
    addr  = {curve_sel[3:0], index}
    word  = {b[W-1:0], dy[W-1:0]}  (2W bits; dy = change of the line across one piece)

Math (integers):
    total = (b << FW) + dy * frac                (units of 2^-(F+FW))
    y     = (total + 2^(FW-1)) >> FW             (round to the format)
    clamp y to 0 .. 2^(W-1)-1

curve_sel: 0 hNa, 1 mP, 2 mCaF, 3 hCaF, 4 mCaS, 5 hCaS, 6 mh, 7 mK1, 8 hK1, 9-15 unused (zero).
mNa has a constant tau (1/tau = 10000 1/s), so it has no table.

Run:  python gen_rtau_cfg.py <output folder>     (writes all 4 tables + 4 test-vector sets)
"""
import os, sys
import numpy as np
import rtau_study as S

NAMES = list(S.RTAU)
CONFIGS = [(18, 128), (18, 256), (32, 128), (32, 256)]

def fmt(W):
    return 7 if W == 18 else 21          # fraction bits F

def sat(v, W):
    lo, hi = -(1 << (W - 1)), (1 << (W - 1)) - 1
    return max(lo, min(hi, v))

def make_tables(W, NB):
    F = fmt(W)
    b_int = [0] * (16 * NB)
    dy_int = [0] * (16 * NB)
    w_mv = 128.0 / NB
    lo = (-64.0 + w_mv * np.arange(NB)) / 1000.0
    hi = lo + w_mv / 1000.0
    for sel, name in enumerate(NAMES):
        b, m = S.coeffs(S.RTAU[name], lo, hi, rel=True)
        for i in range(NB):
            b_int[sel * NB + i] = sat(int(round(b[i] * 2 ** F)), W)
            dy_int[sel * NB + i] = sat(int(round(m[i] * (hi[i] - lo[i]) * 2 ** F)), W)
    return b_int, dy_int

def lut_hw(v, sel, W, NB, b_int, dy_int):
    # EXACTLY what the Verilog does, on integers
    F = fmt(W)
    K = NB.bit_length() - 1
    FW = F + 7 - K
    u = v + (1 << (F + 6))
    u = max(0, min((1 << (F + 7)) - 1, u))
    index = u >> FW
    frac = u & ((1 << FW) - 1)
    a = sel * NB + index
    total = (b_int[a] << FW) + dy_int[a] * frac
    y = (total + (1 << (FW - 1))) >> FW
    return max(0, min((1 << (W - 1)) - 1, y))

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for W, NB in CONFIGS:
        F = fmt(W)
        K = NB.bit_length() - 1
        FW = F + 7 - K
        tag = f"w{W}_n{NB}"
        b_int, dy_int = make_tables(W, NB)
        hexd = (2 * W + 3) // 4
        with open(os.path.join(out, f"rtau_{tag}.mem"), "w") as fo:
            for a in range(16 * NB):
                word = ((b_int[a] & ((1 << W) - 1)) << W) | (dy_int[a] & ((1 << W) - 1))
                fo.write(f"{word:0{hexd}X}\n")

        rnd = np.random.default_rng(462 + W + NB)
        v_lo = int(np.floor(S.L.V_LO * 1000 * 2 ** F))
        v_hi = int(np.ceil(S.L.V_HI * 1000 * 2 ** F))
        vmin, vmax = -(1 << (W - 1)), (1 << (W - 1)) - 1
        tests = []
        for sel in range(16):
            vs = []
            if sel < len(NAMES):
                for i in range(NB):                       # every piece edge, edge-1, edge+1, middle
                    edge = (i << FW) - (1 << (F + 6))
                    vs += [edge - 1, edge, edge + 1, edge + (1 << (FW - 1))]
                vs += [int(x) for x in rnd.integers(v_lo, v_hi, 2000)]
                vs += [int(x) for x in rnd.integers(vmin, vmax, 200)]
            vs += [vmin, vmax, -(1 << (F + 6)) - 1, -(1 << (F + 6)), (1 << (F + 6)) - 1, 1 << (F + 6), 0]
            for v in vs:
                v = max(vmin, min(vmax, v))
                tests.append((sel, v, lut_hw(v, sel, W, NB, b_int, dy_int)))
        ind = (W + 4 + 3) // 4
        outd = (W + 3) // 4
        with open(os.path.join(out, f"tv_in_{tag}.mem"), "w") as fo:     # {sel[3:0], v[W-1:0]}
            for sel, v, y in tests:
                fo.write(f"{(sel << W) | (v & ((1 << W) - 1)):0{ind}X}\n")
        with open(os.path.join(out, f"tv_out_{tag}.mem"), "w") as fo:
            for sel, v, y in tests:
                fo.write(f"{y:0{outd}X}\n")
        with open(os.path.join(out, f"tb_{tag}.vh"), "w") as fo:
            fo.write(f"`define N_TESTS {len(tests)}\n`define TV_IN \"tv_in_{tag}.mem\"\n`define TV_OUT \"tv_out_{tag}.mem\"\n")

        # accuracy of the bit-exact model vs the exact curves (real V range)
        gi = np.unique(np.round(S.GRID * 1000 * 2 ** F).astype(np.int64))[::max(1, len(S.GRID) // 40000)]
        worst, line = 0, []
        for sel, name in enumerate(NAMES):
            ys = np.array([lut_hw(int(v), sel, W, NB, b_int, dy_int) for v in gi]) / 2 ** F
            t = S.RTAU[name](gi / 2 ** F / 1000.0)
            e = np.max(np.abs(ys - t) / t)
            worst = max(worst, e)
            line.append(f"{name} {e*100:.3f}%")
        print(f"{tag}: Q10.{F}, index u[{F+6}:{FW}], frac u[{FW-1}:0], {len(tests)} vectors, "
              f"worst {worst*100:.3f}%  ({', '.join(line)})")

if __name__ == "__main__":
    main()
