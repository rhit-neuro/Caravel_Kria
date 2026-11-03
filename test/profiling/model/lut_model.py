# AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-01 to 2026-11-03.
"""
lut_model.py -- Python golden model for the bit-indexed LUT (Thiago's idea).

Question it answers: how many table entries does each LUT style need to be as
accurate as the old 32-point compare-based LUT?

Run (Vivado's bundled Python has numpy):
    C:/AMDDesignTools/2026.1/Vivado/tps/win64/python-3.13.0/python.exe lut_model.py

Styles compared, for every f_inf curve in the HH Equations docx:
  old32       32 hand-placed points + 32 compares + y = b[i] + m[i]*(x - X[i])
              (docx table for hNa; generated with the same idea for the others)
  fixed       V in mV, add 64 mV, the top bits are the bin number (uniform bins)
  float       bin number = {sign, low exponent bits, top mantissa bits}
              (uniform only inside each power of two)
  scaled      fixed point, but the bin number comes from one multiply,
              so exactly N bins cover the real V range (not a power of two)

What each bin stores ("mode"):
  const_start   one value: the curve at the bin's start
  const_best    one value: halfway between the bin's max and min (smallest worst case)
  lin_start     a line through the curve at both bin edges (like the old table)
  lin_best      that line moved up/down to halve the worst case

Outputs (folder ../results):
  errors.csv        every (curve, style, size, mode) with max / RMS error
  summary.md        smallest table that matches the old LUT's error, per curve
Outputs (folder ../tables):
  LUT_32pt_generated.csv   old-style tables in the docx CSV format
"""
import json, os, struct
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
RESULTS = os.path.join(HERE, "..", "results")
TABLES = os.path.join(HERE, "..", "tables")
ANALYSIS = os.path.join(HERE, "..", "..", "analysis")

# -----------------------------------------------------------------------------
# 1. The curves (docx "Hodgkin Huxley Equations", V in VOLTS)
# -----------------------------------------------------------------------------
def f_inf(a, b):
    # f_inf(a, b, V) = 1 / (1 + e^(a(V+b)))
    return lambda V: 1.0 / (1.0 + np.exp(a * (V + b)))

def fh_inf(V):
    # the one special-form f_inf curve (mh)
    return 1.0 / (1.0 + 2.0 * np.exp(180 * (V + 0.049)) + np.exp(500 * (V + 0.049)))

CURVES = {
    "hNa":  f_inf(500, 0.03),
    "mNa":  f_inf(-150, 0.029),
    "mP":   f_inf(-120, 0.039),
    "mCaF": f_inf(-600, 0.0467),
    "hCaF": f_inf(350, 0.0555),
    "mCaS": f_inf(-420, 0.0472),
    "hCaS": f_inf(360, 0.055),
    "mh":   fh_inf,
    "mK1":  f_inf(-143, 0.021),
    "hK1":  f_inf(111, 0.028),
}

# The only surviving old table (docx). X = breakpoints (V), b = curve value at X, m = slope to next point.
DOCX_X = np.array([-0.044566, -0.04105, -0.039184, -0.037898, -0.036907, -0.036094, -0.035396, -0.034783, -0.03422, -0.033697, -0.033205, -0.032725, -0.032245, -0.031772, -0.031246, -0.030606, -0.029178, -0.0286, -0.028095, -0.027619, -0.027151, -0.02668, -0.026191, -0.025673, -0.025116, -0.024501, -0.023808, -0.023001, -0.022017, -0.02074, -0.018884, -0.015397])
DOCX_B = np.array([0.99931, 0.99603, 0.98997, 0.98109, 0.96934, 0.95465, 0.93691, 0.91617, 0.89188, 0.86397, 0.83234, 0.79616, 0.75448, 0.70805, 0.65092, 0.57516, 0.39873, 0.33177, 0.27843, 0.23316, 0.19397, 0.15975, 0.12959, 0.1031, 0.080009, 0.060117, 0.043263, 0.02932, 0.018137, 0.0096603, 0.0038424, 0.00067414])
DOCX_M = np.array([-0.93376, -3.2478, -6.9041, -11.861, -18.06, -25.423, -33.821, -43.171, -53.38, -64.196, -75.427, -86.901, -98.07, -108.68, -118.32, -123.6, -115.68, -105.8, -94.988, -83.788, -72.602, -61.678, -51.207, -41.384, -32.372, -24.302, -17.278, -11.37, -6.6377, -3.1354, -0.90855, 0])

# -----------------------------------------------------------------------------
# 2. Input range and test points
# -----------------------------------------------------------------------------
# Real V range from the leech simulation (dt = 31.25 us, exponential Euler), mV -> V.
# (leech_ranges_dt0.03125.json is empty, so the _exp file is used.)
rng = json.load(open(os.path.join(ANALYSIS, "leech_ranges_dt0.03125_exp.json")))["ranges"]["V (mV)"]
V_LO, V_HI = rng[0] / 1000.0, rng[1] / 1000.0

# (a) uniform test grid over the real range: 400,001 points, 0.2 uV apart
GRID = np.linspace(V_LO, V_HI, 400001)
# (b) the voltages the neuron actually visits (20 s of simulation, one sample per 0.5 ms)
TRACE = np.array(json.load(open(os.path.join(ANALYSIS, "leech_trace_dt0.03125.json")))["exp"]["V"]) / 1000.0
TRACE = TRACE[(TRACE >= V_LO) & (TRACE <= V_HI)]

OUT_LSB = 2.0 ** -18          # gate output format UQ0.18: outputs are rounded to this step

def round_out(y):
    # store the output as UQ0.18 (like rounding a float to the nearest 1/262144)
    return np.round(np.clip(y, 0.0, 1.0 - OUT_LSB) / OUT_LSB) * OUT_LSB

def errors(y_lut, f, xs):
    e = y_lut - f(xs)
    return np.max(np.abs(e)), np.sqrt(np.mean(e * e))

# -----------------------------------------------------------------------------
# 3. Old-style LUT: 32 breakpoints, compare to find the piece, then a line
# -----------------------------------------------------------------------------
def old_lut_eval(X, b, m, x):
    # piece = last breakpoint that x is >= (what the 32 comparators find).
    # Below X[0] the hardware still uses piece 0 (it only raises Invalid), so we do too.
    piece = np.searchsorted(X, x, side="right") - 1
    piece = np.clip(piece, 0, len(X) - 1)
    return b[piece] + m[piece] * (x - X[piece])

def chord_dev(f, s, e):
    # worst gap between the curve and the straight line from (s, f(s)) to (e, f(e))
    xs = np.linspace(s, e, 257)
    line = f(s) + (f(e) - f(s)) * (xs - s) / (e - s)
    return np.max(np.abs(f(xs) - line))

def greedy_points(f, lo, hi, tol, max_pts):
    # walk left to right, making each piece as long as possible while its error <= tol
    pts = [lo]
    x = lo
    while x < hi and len(pts) <= max_pts:
        if chord_dev(f, x, hi) <= tol:
            pts.append(hi)
            break
        a, z = x, hi                     # binary search for the longest allowed piece
        for _ in range(50):
            mid = 0.5 * (a + z)
            if chord_dev(f, x, mid) <= tol:
                a = mid
            else:
                z = mid
        if a <= x:                       # tolerance too tight to make progress
            return None
        pts.append(a)
        x = a
    return pts if pts[-1] >= hi else None

def make_old32(f, lo=V_LO, hi=V_HI, n=32):
    # choose the smallest worst-case error that 32 points can reach (bisection on tol)
    t_lo, t_hi = 1e-9, 1.0
    for _ in range(60):
        t = np.sqrt(t_lo * t_hi)
        p = greedy_points(f, lo, hi, t, n)
        if p is not None and len(p) <= n:
            t_hi = t
        else:
            t_lo = t
    X = list(greedy_points(f, lo, hi, t_hi, n))
    while len(X) < n:                    # if fewer than n points were needed, split the worst piece
        devs = [chord_dev(f, X[i], X[i + 1]) for i in range(len(X) - 1)]
        i = int(np.argmax(devs))
        X.insert(i + 1, 0.5 * (X[i] + X[i + 1]))
    X = np.array(X)
    b = f(X)
    m = np.append(np.diff(b) / np.diff(X), 0.0)   # slope to the next point; last slope = 0 (docx style)
    return X, b, m

# -----------------------------------------------------------------------------
# 4. Bin LUTs. Each style turns x into a bin number, and gives each bin an
#    interval [lo, hi) of V so we know what values to store.
# -----------------------------------------------------------------------------
def fixed_bins(nbins, offset=0.064, span=0.128):
    # u = V + 64 mV;  bin = u / width, where width is a power of two in the fixed-point LSBs
    width = span / nbins
    lo = -offset + width * np.arange(nbins)
    def index(x):
        return np.clip(np.floor((x + offset) / width).astype(int), 0, nbins - 1)
    return lo, lo + width, index

def scaled_bins(nbins):
    # same as fixed, but the bins cover exactly [V_LO, V_HI] (bin number needs one multiply)
    width = (V_HI - V_LO) / nbins
    lo = V_LO + width * np.arange(nbins)
    def index(x):
        return np.clip(np.floor((x - V_LO) / width).astype(int), 0, nbins - 1)
    return lo, lo + width, index

def float_bins(ne, nm, e_top=122):
    # index = {sign, exponent[ne-1:0], mantissa[22:23-nm]}, plus 2 "near zero" bins.
    # Octaves e_top-(2^ne - 1) .. e_top are covered (e_top = 122 is |V| in [31.25, 62.5) mV).
    n_oct = 2 ** ne
    e_bot = e_top - n_oct + 1
    zmin = 2.0 ** (e_bot - 127)                 # |V| below this goes to the near-zero bin
    nb = 2 * n_oct * 2 ** nm                    # main bins (both signs)
    lo = np.zeros(nb + 2)
    hi = np.zeros(nb + 2)
    for s in (0, 1):
        for k in range(n_oct):
            e = e_bot + k
            for t in range(2 ** nm):
                i = (s << (ne + nm)) | ((e & (n_oct - 1)) << nm) | t
                a = 2.0 ** (e - 127) * (1 + t / 2 ** nm)          # |V| at bin start
                z = 2.0 ** (e - 127) * (1 + (t + 1) / 2 ** nm)    # |V| at bin end
                lo[i], hi[i] = (a, z) if s == 0 else (-z, -a)
    lo[nb], hi[nb] = 0.0, zmin                  # near zero, positive
    lo[nb + 1], hi[nb + 1] = -zmin, 0.0         # near zero, negative

    def index(x):
        # pull the bits straight out of the float32, the way the hardware will
        bits = x.astype(np.float32).view(np.uint32).astype(np.int64)
        s = bits >> 31
        e = (bits >> 23) & 0xFF
        t = (bits >> (23 - nm)) & (2 ** nm - 1)
        i = (s << (ne + nm)) | ((e & (n_oct - 1)) << nm) | t
        i = np.where(e < e_bot, nb + s, i)                       # tiny |V|  -> near-zero bin
        i = np.where(e > e_top, (s << (ne + nm)) | ((e_top & (n_oct - 1)) << nm) | (2 ** nm - 1), i)  # too big -> last bin
        return i
    return lo, hi, index

def bin_coeffs(f, lo, hi, mode):
    # value at bin start (b) and slope (m) for every bin;  y = b + m * (x - lo)
    n = len(lo)
    b = np.zeros(n)
    m = np.zeros(n)
    for i in range(n):
        xs = np.linspace(lo[i], hi[i], 513)
        ys = f(xs)
        if mode == "const_start":
            b[i] = ys[0]
        elif mode == "const_best":
            b[i] = 0.5 * (ys.max() + ys.min())
        else:
            m[i] = (ys[-1] - ys[0]) / (hi[i] - lo[i])
            b[i] = ys[0]
            if mode == "lin_best":
                d = ys - (ys[0] + m[i] * (xs - lo[i]))
                b[i] += 0.5 * (d.max() + d.min())
    return b, m

def bin_eval(lo, b, m, index, x):
    i = index(x)
    return round_out(b[i] + m[i] * (x - lo[i]))

# -----------------------------------------------------------------------------
# 5. Run everything
# -----------------------------------------------------------------------------
def used_bins(index):
    return len(np.unique(index(GRID)))

def main():
    os.makedirs(RESULTS, exist_ok=True)
    os.makedirs(TABLES, exist_ok=True)
    rows = []

    # --- the docx hNa table, as the target
    f = CURVES["hNa"]
    inside = GRID[(GRID >= DOCX_X[0]) & (GRID <= DOCX_X[-1])]
    tgt_max, tgt_rms = errors(old_lut_eval(DOCX_X, DOCX_B, DOCX_M, inside), f, inside)
    full_max, full_rms = errors(old_lut_eval(DOCX_X, DOCX_B, DOCX_M, GRID), f, GRID)
    tr_max, tr_rms = errors(old_lut_eval(DOCX_X, DOCX_B, DOCX_M, TRACE), f, TRACE)
    rows.append(["hNa", "docx32 (own range only)", 32, 32, "lin_start", tgt_max, tgt_rms, "", ""])
    rows.append(["hNa", "docx32", 32, 32, "lin_start", full_max, full_rms, tr_max, tr_rms])
    TARGET = tgt_max

    # --- generated old-style 32-point tables (also written out in the docx CSV format)
    old_tables = {}
    for name, f in CURVES.items():
        X, b, m = make_old32(f)
        old_tables[name] = (X, b, m)
        mx, rm = errors(old_lut_eval(X, b, m, GRID), f, GRID)
        tmx, trm = errors(old_lut_eval(X, b, m, TRACE), f, TRACE)
        rows.append([name, "old32", 32, 32, "lin_start", mx, rm, tmx, trm])

    with open(os.path.join(TABLES, "LUT_32pt_generated.csv"), "w") as fo:
        fo.write("# GENERATED by lut_model.py (not the lost originals). 3 rows per curve: X (V), value at X, slope to next X.\n")
        fo.write("# Curve order: " + ", ".join(CURVES) + "\n")
        for name, (X, b, m) in old_tables.items():
            for row in (X, b, m):
                fo.write(",".join(f"{v:.8g}" for v in row) + "\n")

    # --- the new bin styles
    styles = []
    for n in (32, 64, 128, 256, 512, 1024):
        styles.append(("fixed", n, fixed_bins(n)))
        styles.append(("scaled", n, scaled_bins(n)))
    for total_bits in (5, 6, 7, 8, 9, 10):            # 2^total_bits main bins
        for ne in (2, 3, 4):
            nm = total_bits - 1 - ne
            if nm >= 1:
                styles.append((f"float_e{ne}m{nm}", 2 ** total_bits + 2, float_bins(ne, nm)))

    for name, f in CURVES.items():
        for style, size, (lo, hi, index) in styles:
            used = used_bins(index)
            for mode in ("const_start", "const_best", "lin_start", "lin_best"):
                b, m = bin_coeffs(f, lo, hi, mode)
                mx, rm = errors(bin_eval(lo, b, m, index, GRID), f, GRID)
                tmx, trm = errors(bin_eval(lo, b, m, index, TRACE), f, TRACE)
                rows.append([name, style, size, used, mode, mx, rm, tmx, trm])
        print("done", name)

    with open(os.path.join(RESULTS, "errors.csv"), "w") as fo:
        fo.write("curve,style,table_size,entries_used,mode,max_err,rms_err_uniform,max_err_trace,rms_err_trace\n")
        for r in rows:
            fo.write(",".join(str(v) for v in r) + "\n")

    # --- summary: per curve, the smallest table in each (style family, mode) with max_err <= TARGET
    fam = lambda s: "float" if s.startswith("float") else s
    md = []
    md.append("# Bit-indexed LUT: Python golden model results\n")
    md.append(f"V range: {V_LO*1e3:.2f} to {V_HI*1e3:.2f} mV. Test points: {len(GRID)} uniform, {len(TRACE)} from the 20 s neuron trace.\n")
    md.append(f"**Target (docx hNa 32-pt table, inside its own range): max err = {TARGET:.3e}, RMS = {tgt_rms:.3e}.**")
    md.append(f"Same docx table over the full V range (hardware extrapolates piece 0 below X[0]): max = {full_max:.3e}.\n")
    md.append("## Old-style 32-point tables (generated, best placement)\n")
    md.append("| curve | max err | RMS err | meets target? |\n|---|---|---|---|")
    for r in rows:
        if r[1] == "old32":
            md.append(f"| {r[0]} | {r[5]:.2e} | {r[6]:.2e} | {'yes' if r[5] <= TARGET else 'NO'} |")
    md.append("\n## Smallest bin table that meets the target (entries stored / entries actually used)\n")
    modes = ("const_start", "const_best", "lin_start", "lin_best")
    md.append("| curve | style | " + " | ".join(modes) + " |\n|---|---|" + "---|" * len(modes))
    for name in CURVES:
        for family in ("fixed", "scaled", "float"):
            cells = []
            for mode in modes:
                ok = [r for r in rows if r[0] == name and fam(r[1]) == family and r[4] == mode and r[5] <= TARGET]
                if ok:
                    best = min(ok, key=lambda r: (r[2], r[5]))
                    tag = f" ({best[1][6:]})" if family == "float" else ""
                    cells.append(f"{best[2]} / {best[3]}{tag}")
                else:
                    cells.append("> max tried")
            md.append(f"| {name} | {family} | " + " | ".join(cells) + " |")
    open(os.path.join(RESULTS, "summary.md"), "w").write("\n".join(md) + "\n")
    print("\n".join(md))

if __name__ == "__main__":
    main()
