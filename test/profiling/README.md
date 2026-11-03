# Bit-indexed f_inf LUT: RTL, simulations and profiling report

> AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-01 to 2026-11-03.

Full results are in `LUT_Profiling_Results.md`: timing at 100–600 MHz, resources, accuracy, and board tests.

| Folder | What is in it |
|---|---|
| `rtl/` | The LUT in 5 pipeline depths: `lut_fixed_p3.v`, `lut_fixed_p4.v`, `lut_fixed.v` (5 stages), `lut_fixed_p6.v`, `lut_fixed_p7.v`. Also `lut_axi.v` (AXI-Lite register block with a cycle counter, used for the board test) and `lut_fixed.mem` (the table: 4,096 x 42 bits, 10 curves). |
| `sim/` | xsim testbench for the LUT alone: 32,352 test vectors, checked bit for bit. Run `run_sim.bat lut_fixed_p4` (or `lut_fixed`, `_p3`, `_p6`, `_p7`). |
| `sim_axi/` | xsim testbench for the register block + LUT, driven over AXI: 4,044 single lookups and 4 bursts. Run `run_sim.bat 4` (the stage count: 3, 4, 5, 6 or 7). |
| `model/` | Python bit-exact model. `gen_fixed_lut.py` regenerates `lut_fixed.mem` and the test vectors. `lut_model.py` is the design study it imports. |

## Notes
- The `.bat` files expect Vivado 2026.1 at `C:\AMDDesignTools\2026.1`. Run Vivado builds from a local drive, not a network share.
- `model/lut_model.py` reads the leech V-range files from `../../analysis/`: `leech_ranges_dt0.03125_exp.json` and `leech_trace_dt0.03125.json`. Fix that path before regenerating the tables. The `.mem` files are already included, so the simulations run without it.
