# 1/tau LUT: RTL, simulations and profiling report

> AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-09 to 2026-11-10.

Results: `RTAU_Profiling_Results.md` (accuracy, highest passing clock and resources for every configuration).

| Folder | What is in it |
|---|---|
| `rtl/` | `rtau_lut_s4.v`, `rtau_lut_s6.v`, `rtau_lut_s7.v`: the 1/tau LUT at 4, 6 and 7 pipeline stages. Parameters: `W` (18 or 32 bits, one format for every number), `NB_LOG2` (7 = 128 or 8 = 256 samples per curve), `RAM_BLOCK` (1 = block RAM, 0 = distributed RAM). `rtau_gate_s6.v` + `rtau_bank_s6.v`: one small table per gate, so 9 gates read in parallel. `rtau_w*_n*.mem`: the tables. |
| `sim/` | `run_sim.bat <module> <W> <samples> <ram_block>` (e.g. `run_sim.bat rtau_lut_s6 32 256 1`), and `run_bank_sim.bat <W> <samples> <ram_block>`. Each checks every answer bit for bit against the Python model. |
| `model/` | `gen_rtau_cfg.py` (bit-exact model, tables, test vectors), `gen_rtau_bank_tv.py`, `rtau_study.py` (the 9 exact 1/tau curves), `uniform_format_study.py`. |

The `.bat` files expect Vivado 2026.1 at `C:\AMDDesignTools\2026.1`. `model/lut_model.py` reads the leech V range from `../../analysis/`. The `.mem` files are included, so the sims run without it.
