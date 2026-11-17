# AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-09.
"""
gen_rtau_bank_tv.py -- test vectors for rtau_bank_s6 (9 gates, 9 parallel lookups of the same V).
For each V: the 9 expected outputs from the same bit-exact model as gen_rtau_cfg.py.
Run:  python gen_rtau_bank_tv.py <output folder>
Writes tvb_in_w<W>_n<N>.mem (one V per line), tvb_out_w<W>_n<N>.mem (9 lines per V), tbb_w<W>_n<N>.vh
"""
import os, sys
import numpy as np
import gen_rtau_cfg as G
import rtau_study as S

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    for W, NB in G.CONFIGS:
        F = G.fmt(W); K = NB.bit_length() - 1; FW = F + 7 - K
        b, dy = G.make_tables(W, NB)
        rnd = np.random.default_rng(900 + W + NB)
        vmin, vmax = -(1 << (W - 1)), (1 << (W - 1)) - 1
        vs = []
        for i in range(NB):
            e = (i << FW) - (1 << (F + 6))
            vs += [e - 1, e, e + 1, e + (1 << (FW - 1))]
        vs += [int(x) for x in rnd.integers(int(S.L.V_LO * 1000 * 2 ** F), int(S.L.V_HI * 1000 * 2 ** F), 2000)]
        vs += [int(x) for x in rnd.integers(vmin, vmax, 200)]
        vs += [vmin, vmax, -(1 << (F + 6)) - 1, -(1 << (F + 6)), (1 << (F + 6)) - 1, 1 << (F + 6), 0]
        vs = [max(vmin, min(vmax, v)) for v in vs]
        tag = f"w{W}_n{NB}"
        d = (W + 3) // 4
        with open(os.path.join(out, f"tvb_in_{tag}.mem"), "w") as fo:
            for v in vs:
                fo.write(f"{v & ((1 << W) - 1):0{d}X}\n")
        with open(os.path.join(out, f"tvb_out_{tag}.mem"), "w") as fo:
            for v in vs:
                for c in range(9):
                    fo.write(f"{G.lut_hw(v, c, W, NB, b, dy):0{d}X}\n")
        with open(os.path.join(out, f"tbb_{tag}.vh"), "w") as fo:
            fo.write(f"`define N_TESTS {len(vs)}\n`define TV_IN \"tvb_in_{tag}.mem\"\n`define TV_OUT \"tvb_out_{tag}.mem\"\n")
        print(tag, len(vs), "inputs x 9 gates")

if __name__ == "__main__":
    main()
