# AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-09.
"""
uniform_format_study.py -- what happens when EVERY number in the LUT uses the same
signed fixed-point format Q(I).(F) with W = 1 + I + F bits (team request, 2026-11-09).

Numbers that share the format: V (mV), the stored offset b, the stored slope dy
(change across one piece), and the output y. The position inside the piece (frac) is
just the low bits of V, so it has the same LSB as V.

Pieces: 128 (1 mV) or 256 (0.5 mV) over -64 .. +64 mV, found by bit slicing.
Errors measured over the real V range (-62.48 .. +18.32 mV):
  f_inf: max ABSOLUTE error (old LUT: 7.1e-4 inside its own range)
  1/tau: max RELATIVE error (old tau tables: 0.026% .. 1.98%)
Run:  python uniform_format_study.py
"""
import numpy as np
import lut_model as L      # 10 f_inf curves, real V range
import rtau_study as S     # 9 exact 1/tau curves, line fit

def q(x, F):                                    # round to the format's LSB (2^-F)
    return np.round(x * 2.0 ** F) / 2.0 ** F

def worst(curves, nb, F, relative):
    w_mv = 128.0 / nb
    lo = (-64.0 + w_mv * np.arange(nb)) / 1000.0
    hi = lo + w_mv / 1000.0
    Vmv = q(S.GRID * 1000.0, F)                 # V rounded to the format
    i = np.clip(((Vmv + 64) // w_mv).astype(int), 0, nb - 1)
    frac = (Vmv + 64 - i * w_mv) / w_mv         # 0..1, exact: it is just the low bits of V
    out = 0.0
    for f in curves.values():
        b, m = S.coeffs(f, lo, hi, rel=relative)
        bq = q(b, F)
        dyq = q(m * (hi - lo), F)
        y = q(bq[i] + dyq[i] * frac, F)
        t = f(Vmv / 1000.0)
        e = np.abs(y - t) / t if relative else np.abs(y - t)
        out = max(out, e.max())
    return out

def main():
    # f_inf alone needs 7 integer bits (V to +-128 mV); 1/tau needs 10 (up to 940 1/s)
    cases = [("18-bit, f_inf format Q7.10", 10), ("18-bit, 1/tau format Q10.7", 7),
             ("32-bit, f_inf format Q7.24", 24), ("32-bit, 1/tau format Q10.21", 21)]
    for label, F in cases:
        for nb in (128, 256):
            ef = worst(L.CURVES, nb, F, relative=False)
            er = worst(S.RTAU, nb, F, relative=True)
            print(f"{label:28s} {nb} samples:  f_inf abs err {ef:.2e}   1/tau rel err {er*100:.3f} %")

if __name__ == "__main__":
    main()
