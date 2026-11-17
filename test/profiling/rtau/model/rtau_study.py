# AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-09.
"""
rtau_study.py -- design study for the 1/tau LUT (same bit-indexed idea as the f_inf LUT).

Questions it answers (all measured over the real V range, -62.48 .. +18.32 mV):
  1. How wide can each piece be and still hit the target?   (piece = bin of the V axis)
  2. How many output bits does one fixed-point format need?  (1/tau runs 0.18 .. 940 1/s)

Target: max RELATIVE error <= 2.622e-4 on every curve
        (= the best old 32-point tau table, hK1; Rohan picked option (b) on 2026-11-09).

Run:  python rtau_study.py
"""
import numpy as np
import lut_model as L                     # for the real V range (V_LO, V_HI, in volts)

TARGET = 2.622e-4

def tau_generic(a, b, c, d):
    return lambda V: c + d / (1 + np.exp(a * (V + b)))

# tau(V) in seconds, V in volts. Source: Get Familiar/Hodgkin Huxley Equations.docx
TAU = {
    "hNa":  lambda V: 0.004 + 0.006 / (1 + np.exp(500 * (V + 0.028))) + 0.01 / np.cosh(300 * (V + 0.027)),
    "mP":   tau_generic(400, 0.057, 0.01, 0.2),
    "mCaF": lambda V: 0.011 + 0.024 / np.cosh(-330 * (V + 0.0467)),
    "hCaF": tau_generic(270, 0.055, 0.06, 0.31),
    "mCaS": tau_generic(-400, 0.0487, 0.005, 0.134),
    "hCaS": tau_generic(-250, 0.043, 0.2, 5.25),
    "mh":   tau_generic(-100, 0.073, 0.7, 1.7),
    "mK1":  tau_generic(150, 0.016, 0.001, 0.011),
    "hK1":  tau_generic(-143, 0.013, 0.5, 0.2),
}
# mNa: tau = 0.0001 s at every V -> 1/tau = 10000 1/s, a constant, no LUT.
RTAU = {n: (lambda f: (lambda V: 1.0 / f(V)))(f) for n, f in TAU.items()}

GRID = np.linspace(L.V_LO, L.V_HI, 400001)       # real V range, volts

def coeffs(f, lo, hi, rel):
    # one line per piece: through the curve at both ends, then shifted to halve the worst error
    # rel=True halves the worst RELATIVE error instead of the absolute one
    n = len(lo); b = np.zeros(n); m = np.zeros(n)
    for i in range(n):
        xs = np.linspace(lo[i], hi[i], 257)
        ys = f(xs)
        m[i] = (ys[-1] - ys[0]) / (hi[i] - lo[i])
        line = ys[0] + m[i] * (xs - lo[i])
        d = (ys - line) / ys if rel else (ys - line)
        shift = 0.5 * (d.max() + d.min())
        b[i] = ys[0] + (shift * ys.mean() if rel else shift)
    return b, m

def max_rel_err(f, bin_mv, rel, out_frac=None):
    nb = int(round(128 / bin_mv))
    lo = (-64.0 + bin_mv * np.arange(nb)) / 1000.0
    hi = lo + bin_mv / 1000.0
    b, m = coeffs(f, lo, hi, rel)
    i = np.clip(((GRID * 1000 + 64) // bin_mv).astype(int), 0, nb - 1)
    y = b[i] + m[i] * (GRID - lo[i])
    if out_frac is not None:                                    # round to the output's LSB
        y = np.round(y * 2 ** out_frac) / 2 ** out_frac
    t = f(GRID)
    return np.max(np.abs(y - t) / t)

def main():
    print("1/tau over the real V range (1/s):")
    for n, f in RTAU.items():
        t = f(GRID)
        print(f"  {n:5s} {t.min():9.4f} .. {t.max():9.3f}")

    print(f"\n1. Piece width (no rounding yet). Max relative error, target {TARGET:.3e}")
    widths = [1.0, 0.5, 0.25, 0.125]
    for rel in (False, True):
        print(f"   line shifted to halve the worst {'RELATIVE' if rel else 'absolute'} error")
        print("   curve  " + "".join(f"{w:>11} mV" for w in widths))
        worst = [0] * len(widths)
        for n, f in RTAU.items():
            e = [max_rel_err(f, w, rel) for w in widths]
            worst = [max(a, b) for a, b in zip(worst, e)]
            print(f"   {n:6s}" + "".join(f"{x:14.3e}" for x in e))
        print("   WORST " + "".join(f"{x:14.3e}" for x in worst) + "\n")

    print("2. Output rounding: unsigned fixed point, 10 integer bits (max 940 < 1024) + F fraction bits")
    print("   (relative-shift lines; pieces of 0.5 and 0.25 mV)")
    for w in (0.5, 0.25):
        for F in (12, 14, 15, 16, 17, 18):
            worst = max(max_rel_err(f, w, True, F) for f in RTAU.values())
            print(f"   {w} mV, F = {F:2d} ({10 + F} bits): worst {worst:.3e}  {'OK' if worst <= TARGET else 'over target'}")

if __name__ == "__main__":
    main()
