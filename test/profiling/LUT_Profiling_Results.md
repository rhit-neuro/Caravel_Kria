# LUT profiling: bit-indexed fixed-point LUT vs. current 32-breakpoint LUT

> AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-01 to 2026-11-03.

KR260 (`xck26-sfvc784-2LV-c`), Vivado 2026.1. Session 2026-11-01/02.

## What was simulated

**Function.** Steady-state gating curves f_inf(V) = 1 / (1 + e^(a(V+b))), V in volts. The table is indexed by V itself: a(V+b) is built into the table contents, so the LUT needs no multiply or add in front of it. Only the 10 f_inf curves were built and tested. The tau curves have not been done yet.

| # (curve_sel) | Curve | a | b (V) |
|---|---|---:|---:|
| 0 | hNa | 500 | 0.03 |
| 1 | mNa | -150 | 0.029 |
| 2 | mP | -120 | 0.039 |
| 3 | mCaF | -600 | 0.0467 |
| 4 | hCaF | 350 | 0.0555 |
| 5 | mCaS | -420 | 0.0472 |
| 6 | hCaS | 360 | 0.055 |
| 7 | mh | special |  |
| 8 | mK1 | -143 | 0.021 |
| 9 | hK1 | 111 | 0.028 |

mh = 1 / (1 + 2e^(180(V+0.049)) + e^(500(V+0.049))). curve_sel 10-15 are empty (table words are zero).

**Points per curve.**
- Old LUT: 32 breakpoints. The only surviving table is the docx hNa table, which covers -44.6 to -15.4 mV, so the old-LUT error was measured on hNa only.
- New LUT: 256 straight-line pieces per curve, each 0.5 mV wide. Each piece stores its own offset b and slope dy, fitted to the curve over that piece. The slope is the line through the curve at the piece's two ends. That line is then shifted up or down to halve the worst error, so neighbouring pieces do not quite meet at the edges.
- In total, 10 curves x 256 = 2,560 pieces are used. The table is 4,096 words x 42 bits (16 curve slots x 256), stored in 5 BRAM36 tiles.

**Input and output ranges.**
- **Input V:** 27-bit signed Q7.19 in mV, so the port accepts -128 to +128 mV in steps of 2^-19 mV.
- **Table coverage:** -64 to +64 mV. Inputs outside that range are clamped to the nearest edge of the table.
- **Real neuron range:** -62.48 to +18.32 mV, taken from the leech simulation trace with dt = 0.03125 ms. It falls on 162 of the 256 pieces.
- **Output y:** 18-bit unsigned UQ0.18, from 0 to 1 - 2^-18, in steps of 2^-18 (about 3.8e-6). It is clamped to that range.
- **Accuracy reference:** max |error| against the exact curve in double precision, over -62.48 to +18.32 mV.

**Test inputs.** Every hardware answer was checked bit for bit against the Python model (`gen_fixed_lut.py`), not just checked for being close.
- **xsim** (RTL and post-route gate-level): 32,352 inputs. For each of the 10 curves:
  - every piece's edge, edge - 1 LSB and edge + 1 LSB, plus its middle (1,024 inputs);
  - 2,000 random V in the real range;
  - 200 random V anywhere in -128 to +128 mV;
  - 7 extreme values (the ends of the input range and of the table).
  - The 7 extreme values were also run on each empty slot (curve_sel 10-15).
- **Board:** every 8th xsim input, which is 4,044 single lookups (404 per curve) read through AXI.
- **Board bursts:** 4 bursts at one lookup per clock, checked by sum:
  - hNa: 1,000 steps from -62 mV;
  - mCaF: 20,000 steps from -64 mV;
  - mh: 5,000 steps going down from -40 mV;
  - hK1: 777 repeats at -30 mV.

## Definitions

- **New LUT:** V in Q7.19 mV (27-bit) -> add 64 mV -> top 8 bits = bin (256 bins of 0.5 mV), low 18 bits = position in bin; y = b + dy*frac (one DSP multiply-add), output UQ0.18. One table holds all 10 f_inf curves (curve_sel). No comparisons.
- **Old LUT:** inherited Indexing_Unit (32 FloatingCompare) + Memory_Units + LUT_MAC_Module, FP32, unchanged, 1 clock.
- **Best clock** = highest clock where setup (WNS), hold (WHS) and pulse width (WPWS) all pass. Margins under 0.1 ns: plan one step lower.
- **x** = cycles - 1 (the neuron-core diagram's f_inf box is (1 + x); the first clock overlaps the step before the LUT).
- **Throughput:** every version takes one new input per clock.
- **Where each number comes from:** OOC = out-of-context synth + place + route of the LUT alone (registers on all pins); Board build = full KR260 design (Zynq PS + SmartConnect + register block + LUT), routed; Board = measured on the real KR260.

## Where the table lives, and how the block RAM read is counted

**The table is in the PL, not the PS.** Block RAM (BRAM) is on-chip SRAM built into the FPGA fabric, next to the logic and the DSP. The table is baked into the bitstream: `$readmemh("lut_fixed.mem")` in the Verilog becomes the BRAMs' starting contents. So the table is already inside the 5 BRAM tiles as soon as the bitstream loads. A lookup never leaves the PL, and it never touches the PS or DDR.

```
PS (ARM + DDR)                     PL (FPGA fabric)
-------------                      ------------------------------------------
Python test script  --AXI bus-->   registers --> [address] --> [BRAM] --> [DSP] --> y
  (slow, 100 MHz,                                 table lives here, inside the PL
   through SmartConnect)
```

**Why one clock is enough.** A BRAM takes an address on one clock edge and has the data ready by the next edge. Vivado's timing analysis confirms the read fits: setup, hold and pulse width all pass at 400 MHz (2.5 ns) for the 4-stage version, and at 500 MHz for the 6-stage version. The BRAM's own limit is a 1.709 ns minimum period (about 585 MHz), shown by the pulse-width check (WPWS). That limit is why every version fails at 600 MHz. Adding pipeline stages cannot fix it.

**The RAM read is included in every cycle count in this report.**

| Version | Stages | Clocks spent on the RAM read |
|---|---|---|
| p3 | address -> **RAM read** -> multiply+add+round | 1 of 3 |
| p4 | address -> **RAM read** -> multiply -> add/round | 1 of 4 |
| p5 (lut_fixed) | input reg -> address -> **RAM read** -> multiply -> add/round | 1 of 5 |
| p6 | p5 with add-b and round/clamp split into two stages | 1 of 6 |
| p7 | p6 plus the RAM's built-in output register | **2** of 7 |

**How the latency was measured.** It was measured, not just counted from the design:
- In xsim, both RTL and post-route gate-level, the testbench counted clock edges from input to output.
- On the board, the PL cycle counter read 3, 4 and 6 for the p3, p4 and p6 builds.

**What the latency does not include.** The board test sends V and reads y through AXI from the PS. That round trip is much slower than the LUT. It was not measured, and it is not part of any latency in this report: the LATENCY register counts LUT clocks inside the PL. The burst test shows the LUT without AXI in the way: the PL feeds it a new V every clock, and N lookups take N + stages cycles. In the real neuron core, V comes from the PL step before the LUT, so the AXI cost does not apply there.

## LUT: new design vs. current design

| | Current (32 breakpoints, FP32) | New, 4 stages | New, 6 stages |
|---|---:|---:|---:|
| Max error, f_inf curves (real V range) | 1.6e-02 (hNa; 7.1e-04 inside its own -44.6..-15.4 mV) | 5.4e-04 (worst of 10 curves) | 5.4e-04 |
| LUTs | 2468 | 56 | 38 |
| FFs | 3105 | 42 | 85 |
| Block RAM tiles | 0 | 5 | 5 |
| DSPs | 2 | 1 | 1 |
| Cycles (x) | 1 (0) | 4 (3) | 6 (5) |
| Best clock (OOC) | 50 MHz (est. Fmax ~70 MHz) | 400 MHz | 500 MHz |
| Latency at best clock | 20.0 ns | 10.00 ns | 12.00 ns |
| Lookups per second at best clock | 50 M | 400 M | 500 M |

## New LUT: best clock per pipeline depth (OOC)

| Version (stages) | Cycles | x | Best clock | Latency at best clock | Est. Fmax (setup only) | LUT | FF | BRAM tiles | DSP |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| lut_fixed_p3 (3) | 3 | 2 | 200 MHz | 15.00 ns | ~278 MHz | 48 | 18 | 5 | 1 |
| lut_fixed_p4 (4) | 4 | 3 | 400 MHz | 10.00 ns | ~450 MHz | 56 | 42 | 5 | 1 |
| lut_fixed (5) | 5 | 4 | 400 MHz | 12.50 ns | ~444 MHz | 57 | 91 | 5 | 1 |
| lut_fixed_p6 (6) | 6 | 5 | 500 MHz | 12.00 ns | ~524 MHz | 38 | 85 | 5 | 1 |
| lut_fixed_p7 (7) | 7 | 6 | 400 MHz | 17.50 ns | ~488 MHz | 34 | 91 | 5 | 1 |

## New LUT: WNS (ns) for every stage count x clock (OOC). ✅ = setup, hold and pulse width all pass

| Stages | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---:|---:|---:|---:|---:|---:|
| 3 | ✅ 6.089 | ✅ 1.145 | ❌ -0.325 | ❌ -1.141 | ❌ -1.597 | ❌ -1.963 (WPWS -0.042) |
| 4 | ✅ 7.538 | ✅ 2.574 | ✅ 0.866 | ✅ 0.110 | ❌ -0.220 | ❌ -1.144 (WPWS -0.042) |
| 5 | ✅ 7.053 | ✅ 2.083 | ✅ 0.716 | ✅ 0.105 | ❌ -0.253 | ❌ -1.136 (WPWS -0.042) |
| 6 | ✅ 7.061 | ✅ 2.267 | ✅ 0.854 | ✅ 0.101 | ✅ 0.093 | ❌ -0.346 (WPWS -0.042) |
| 7 | ✅ 6.724 | ✅ 2.345 | ✅ 0.678 | ✅ 0.110 | ❌ -0.049 | ❌ -0.405 (WPWS -0.042) |

## Fewest stages that close timing at each clock

| Clock | OOC: fewest stages (cycles / x / ns) | Full board build: stages used, WNS / WHS / WPWS | On the board |
|---|---|---|---|
| 100 MHz | 3 (3 / 2 / 30.00 ns) | 3 stages: 5.956 / 0.022 / 2.000 -> met | PASS: clock 100.00 MHz, 0 wrong of 4044, latency 3 clk, bursts 4/4 OK, up to 100.0 M lookups/s |
| 200 MHz | 3 (3 / 2 / 15.00 ns) | 3 stages: 1.149 / 0.025 / 1.738 -> met | PASS: clock 200.00 MHz, 0 wrong of 4044, latency 3 clk, bursts 4/4 OK, up to 200.0 M lookups/s |
| 300 MHz | 4 (4 / 3 / 13.33 ns) | 4 stages: 0.581 / 0.021 / 0.905 -> met | PASS: clock 300.00 MHz, 0 wrong of 4044, latency 4 clk, bursts 4/4 OK, up to 299.9 M lookups/s |
| 400 MHz | 4 (4 / 3 / 10.00 ns) | 4 stages: 0.090 / 0.013 / 0.488 -> met | PASS: clock 400.00 MHz, 0 wrong of 4044, latency 4 clk, bursts 4/4 OK, up to 399.9 M lookups/s |
| 500 MHz | 6 (6 / 5 / 12.00 ns) | 6 stages: 0.020 / 0.010 / 0.238 -> met | PASS: clock 500.00 MHz, 0 wrong of 4044, latency 6 clk, bursts 4/4 OK, up to 499.8 M lookups/s |
| 600 MHz | none of 3-7 | 7 stages: -0.307 / 0.021 / -0.042 -> NOT met | not loaded (timing failed) |
| 100MHz (5 stages, pl_clk0 direct) | | | PASS: clock 100.00 MHz, 0 wrong of 4044, latency 5 clk |

## Full board-design builds (PS + SmartConnect + register block + LUT, LUT clock from an MMCM)

| Build | WNS | WHS | WPWS | Met | Slowest path | Whole PL: LUT / FF / RAMB36 / DSP |
|---|---:|---:|---:|---|---|---|
| 100MHz_p3 | 5.956 | 0.022 | 2.000 | yes | lut0/inst/g_lut.lut/prod/DSP_A_B_DATA_INST/CLK -> lut0/inst/g_lut.lut/y_out_reg[0]/R (levels 9) | 932 / 1451 / 5 / 1 |
| 200MHz_p3 | 1.149 | 0.025 | 1.738 | yes | lut0/inst/g_lut.lut/prod/DSP_A_B_DATA_INST/CLK -> lut0/inst/g_lut.lut/y_out_reg[10]/R (levels 9) | 927 / 1451 / 5 / 1 |
| 300MHz_p4 | 0.581 | 0.021 | 0.905 | yes | rst_lut/U0/ACTIVE_LOW_PR_OUT_DFF[0].FDRE_PER_N/C -> lut0/inst/latency_reg[10]/R (levels 0) | 928 / 1475 / 5 / 1 |
| 400MHz_p4 | 0.090 | 0.013 | 0.488 | yes | lut0/inst/g_lut.lut/prod3_reg/DSP_OUTPUT_INST/CLK -> lut0/inst/g_lut.lut/y_out_reg[10]/R (levels 5) | 938 / 1493 / 5 / 1 |
| 500MHz_p6 | 0.020 | 0.010 | 0.238 | yes | lut0/inst/burst_count_reg[7]/C -> lut0/inst/burst_done_reg/D (levels 7) | 924 / 1546 / 5 / 1 |
| 600MHz_p7 | -0.307 | 0.021 | -0.042 | NO | lut0/inst/burst_n_reg[13]/C -> lut0/inst/burst_v_reg[25]/D (levels 7) | 938 / 1560 / 5 / 1 |

## Current (old) LUT, OOC

FF count includes its 33 output-register bits; the V/M/B tables alone are 3 x 32 x 32 = 3,072 FFs.

| Clock | WNS | WHS | Met | Est. Fmax | LUT | FF | DSP | Slowest path (levels) |
|---|---:|---:|---|---:|---:|---:|---:|---|
| 100 MHz | -4.699 | 0.172 | NO | 68.0 | 2468 | 3105 | 2 | x_r_reg[14]/C -> y_out_reg[21]/D (43) |
| 75 MHz | -1.031 | 0.195 | NO | 69.6 | 2480 | 3105 | 2 | x_r_reg[0]/C -> y_out_reg[27]/D (44) |
| 50 MHz | 0.819 | 0.141 | yes | 52.1 | 2360 | 3105 | 2 | x_r_reg[1]/C -> y_out_reg[17]/D (48) |

## Accuracy (Python bit-exact model = what the hardware computes; max |error| vs the true curve, V = -62.48..+18.32 mV)

| Curve | hNa | mNa | mP | mCaF | hCaF | mCaS | hCaS | mh | mK1 | hK1 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| New LUT max error | 3.8e-04 | 3.5e-05 | 2.3e-05 | 5.4e-04 | 1.9e-04 | 2.7e-04 | 2.0e-04 | 1.2e-04 | 3.2e-05 | 2.0e-05 |

Target = old hNa table inside its own range, 7.12e-04. All 10 curves are under it. Over the full V range the old table's error is 1.6e-02, because below -44.6 mV the old hardware keeps extending piece 0's line.

## Verification

- RTL (xsim): 32,352 test vectors per version (all 10 curves, every bin edge +-1, mid-bin, random, out-of-range), 0 mismatches vs. the Python bit-exact model, for 3/4/5/6/7 stages.
- Register block + LUT (xsim, through AXI-Lite): 4,044 single lookups + 4 bursts, 0 mismatches, for 3/4/5/6/7 stages.
- Gate-level (routed netlists, xsim): 30 of 30 netlists give 0 mismatches on all 32,352 vectors.
- Board: 6 builds tested on the KR260 (see table above).

## Findings

- **Equal bins need more entries than hand-placed points, but no comparisons.** 256 bins + a line per bin beat the old 32-point table on all 10 f_inf curves. One value per bin (no slope) would need ~16,384 bins for hNa (measured: 16,384 bins -> 4.9e-4), so the slope is required.
- **Fixed point beats float indexing** for the same table size (hNa, 256 entries, line per bin: fixed 3.8e-4, float-bit index 1.4e-3), because float bins are finest near 0 V, not where the curves bend.
- **The old LUT has a range bug:** below its first breakpoint (-44.6 mV) the hardware keeps using piece 0's line, so over the real V range its error is 1.6e-2.
- **Where the time goes:** 3-4 stages are limited by the last stage (multiply/add + round + clamp). Splitting add-b from round/clamp (6 stages) reaches 500 MHz. At 7 stages the limit moves to stage 2 (+64 mV add and clamp feeding the RAM address).
- **600 MHz is not reachable with this block RAM table:** every version shows pulse-width slack -0.042 ns (RAMB36 minimum period 1.709 ns, ~585 MHz), even at 7 stages. Unverified: Vivado used the RAM output register (DOA_REG=1) on only some of the 5 RAM tiles, so a fully registered RAM might do better. Not tried: LUTRAM/smaller table, or URAM.
- **Full board design tracks the OOC results:** 100/200 MHz with 3 stages, 300/400 MHz with 4, 500 MHz with 6 all met timing in the complete KR260 design and passed on the board. At 600 MHz the board build also fails, first on the register block's burst logic (my test harness, not the LUT) and on the RAM pulse width.
- **Board:** each tested build gave 0 wrong answers on 4,044 lookups (bit-exact vs Python), latency = stage count on every lookup (hardware counter), and bursts of N lookups took N + stages clocks (1 lookup per clock). Measured clock = requested clock in every case.
- **Board SSH dropped at 02:57 on 2026-11-02 after ~1 h 33 min uptime**, even with an SSH every 30 min (SD card failing). All board tests had finished before that.

## Recommendations

- Use the bit-indexed fixed-point LUT (256 bins, line per bin). Pick the depth by clock: 3 stages up to 200 MHz, 4 stages at 300-400 MHz, 6 stages at 500 MHz. 400 MHz with 4 stages (10 ns, x = 3) is the sweet spot; its margin is ~0.1 ns, so plan 300 MHz if the full neuron core is crowded.
- In the neuron-core diagram, f_inf box (1 + x): x = 2 (3 stages), 3 (4 stages) or 5 (6 stages).
- The same table can hold all 10 f_inf curves (curve_sel); tau curves still need their own error target (not done yet).
- Replace the inherited LUT: it needs 2,300-2,500 LUTs + ~3,100 FFs, reaches only 50 MHz (fails 75 MHz), and its error over the real V range is 1.6e-2.

## Files

- Python: `model/lut_model.py` (design study), `model/gen_fixed_lut.py` (bit-exact model, table, test vectors), `model/make_report.py` (this report)
- RTL: `rtl/lut_fixed.v` (5 stages) and `rtl/lut_fixed_p3/p4/p6/p7.v`; board: `board_rtl/lut_axi.v` (AXI-Lite register block)
- Tables: `tables/LUT_fixed256_linbest.csv`, `tables/LUT_32pt_generated.csv` (generated; the docx's LUT CSV folder was not available)
- Sweep: `reports/lut_sweep.csv`, `reports/funcsim_results.txt`; board: `board_results/results_*.txt`, `board_builds/*/result.txt`

## Every OOC run

| Version | Stages | Clock | Latency (ns) | WNS | WHS | WPWS | Met | Est. Fmax | LUT | FF | BRAM | DSP | Slowest path (start -> end, levels) |
|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|---|
| lut_fixed_p3 | 3 | 100 | 30.000 | 6.089 | 0.092 | 4.238 | yes | 255.7 | 48 | 18 | 5 | 1 | dut/prod/DSP_A_B_DATA_INST/CLK -> dut/y_out_reg[10]/R (10) |
| lut_fixed_p3 | 3 | 200 | 15.000 | 1.145 | 0.092 | 1.738 | yes | 259.4 | 48 | 18 | 5 | 1 | dut/prod/DSP_A_B_DATA_INST/CLK -> dut/y_out_reg[10]/R (10) |
| lut_fixed_p3 | 3 | 300 | 9.999 | -0.325 | 0.088 | 0.904 | NO | 273.4 | 54 | 18 | 5 | 1 | dut/prod/DSP_A_B_DATA_INST/CLK -> dut/y_out_reg[13]/R (9) |
| lut_fixed_p3 | 3 | 400 | 7.500 | -1.141 | 0.089 | 0.488 | NO | 274.6 | 55 | 18 | 5 | 1 | dut/prod/DSP_A_B_DATA_INST/CLK -> dut/y_out_reg[3]/D (9) |
| lut_fixed_p3 | 3 | 500 | 6.000 | -1.597 | 0.098 | 0.238 | NO | 278.0 | 67 | 18 | 5 | 1 | dut/prod/DSP_A_B_DATA_INST/CLK -> dut/y_out_reg[13]/R (9) |
| lut_fixed_p3 | 3 | 600 | 5.001 | -1.963 | 0.097 | -0.042 | NO | 275.5 | 65 | 18 | 5 | 1 | dut/prod/DSP_A_B_DATA_INST/CLK -> dut/y_out_reg[2]/R (9) |
| lut_fixed_p4 | 4 | 100 | 40.000 | 7.538 | 0.090 | 4.238 | yes | 406.2 | 48 | 42 | 5 | 1 | dut/addr1_reg_1/CLKARDCLK -> dut/prod3_reg/DSP_A_B_DATA_INST/B[16] (0) |
| lut_fixed_p4 | 4 | 200 | 20.000 | 2.574 | 0.090 | 1.738 | yes | 412.2 | 48 | 42 | 5 | 1 | dut/addr1_reg_0/CLKARDCLK -> dut/prod3_reg/DSP_A_B_DATA_INST/B[3] (0) |
| lut_fixed_p4 | 4 | 300 | 13.332 | 0.866 | 0.090 | 0.904 | yes | 405.4 | 48 | 42 | 5 | 1 | dut/addr1_reg_0/CLKARDCLK -> dut/prod3_reg/DSP_A_B_DATA_INST/B[5] (0) |
| lut_fixed_p4 | 4 | 400 | 10.000 | 0.110 | 0.100 | 0.488 | yes | 418.4 | 56 | 42 | 5 | 1 | dut/addr1_reg_1/CLKARDCLK -> dut/prod3_reg/DSP_A_B_DATA_INST/B[9] (0) |
| lut_fixed_p4 | 4 | 500 | 8.000 | -0.220 | 0.105 | 0.238 | NO | 450.5 | 60 | 78 | 5 | 1 | dut/rounded__0_carry__1_i_1_psdsp_16/C -> dut/prod3_reg/DSP_OUTPUT_INST/ALU_OUT[0] (5) |
| lut_fixed_p4 | 4 | 600 | 6.668 | -1.144 | 0.098 | -0.042 | NO | 355.7 | 59 | 60 | 5 | 1 | dut/prod3_reg/DSP_M_DATA_INST/CLK -> dut/y_out_reg[16]/R (6) |
| lut_fixed | 5 | 100 | 50.000 | 7.053 | 0.064 | 4.238 | yes | 339.3 | 48 | 73 | 5 | 1 | dut/v1_reg[25]/C -> dut/addr2_reg_3/ADDRARDADDR[3] (2) |
| lut_fixed | 5 | 200 | 25.000 | 2.083 | 0.064 | 1.738 | yes | 342.8 | 48 | 73 | 5 | 1 | dut/v1_reg[25]/C -> dut/addr2_reg_3/ADDRARDADDR[4] (2) |
| lut_fixed | 5 | 300 | 16.665 | 0.716 | 0.064 | 0.904 | yes | 382.1 | 48 | 73 | 5 | 1 | dut/v1_reg[24]/C -> dut/addr2_reg_3/ADDRARDADDR[4] (2) |
| lut_fixed | 5 | 400 | 12.500 | 0.105 | 0.064 | 0.488 | yes | 417.5 | 57 | 91 | 5 | 1 | dut/v1_reg[24]/C -> dut/prod4_reg/DSP_A_B_DATA_INST/A[15] (2) |
| lut_fixed | 5 | 500 | 10.000 | -0.253 | 0.063 | 0.238 | NO | 443.9 | 60 | 109 | 5 | 1 | dut/rounded__0_carry__1_i_1_psdsp_6/C -> dut/prod4_reg/DSP_OUTPUT_INST/ALU_OUT[11] (5) |
| lut_fixed | 5 | 600 | 8.335 | -1.136 | 0.059 | -0.042 | NO | 356.8 | 68 | 91 | 5 | 1 | dut/prod4_reg/DSP_M_DATA_INST/CLK -> dut/y_out_reg[12]/R (7) |
| lut_fixed_p6 | 6 | 100 | 60.000 | 7.061 | 0.071 | 4.238 | yes | 340.3 | 34 | 49 | 5 | 1 | dut/v1_reg[25]/C -> dut/addr2_reg_3/ADDRARDADDR[3] (3) |
| lut_fixed_p6 | 6 | 200 | 30.000 | 2.267 | 0.071 | 1.738 | yes | 365.9 | 34 | 49 | 5 | 1 | dut/v1_reg[25]/C -> dut/addr2_reg_3/ADDRARDADDR[3] (3) |
| lut_fixed_p6 | 6 | 300 | 19.998 | 0.854 | 0.064 | 0.904 | yes | 403.4 | 34 | 49 | 5 | 1 | dut/v1_reg[25]/C -> dut/addr2_reg_3/ADDRARDADDR[7] (3) |
| lut_fixed_p6 | 6 | 400 | 15.000 | 0.101 | 0.059 | 0.488 | yes | 416.8 | 34 | 49 | 5 | 1 | dut/addr2_reg_0/CLKARDCLK -> dut/total5_reg/DSP_A_B_DATA_INST/B[0] (0) |
| lut_fixed_p6 | 6 | 500 | 12.000 | 0.093 | 0.063 | 0.238 | yes | 524.4 | 38 | 85 | 5 | 1 | dut/v1_reg[24]/C -> dut/addr2_reg_0/ADDRARDADDR[4] (2) |
| lut_fixed_p6 | 6 | 600 | 10.002 | -0.346 | 0.071 | -0.042 | NO | 496.8 | 53 | 85 | 5 | 1 | dut/v1_reg[24]/C -> dut/addr2_reg_2/ADDRARDADDR[4] (2) |
| lut_fixed_p7 | 7 | 100 | 70.000 | 6.724 | 0.059 | 4.238 | yes | 305.3 | 34 | 91 | 5 | 1 | dut/v1_reg[24]/C -> dut/addr2_reg_2/ADDRARDADDR[5] (2) |
| lut_fixed_p7 | 7 | 200 | 35.000 | 2.345 | 0.059 | 1.738 | yes | 376.6 | 34 | 91 | 5 | 1 | dut/addr2_reg_1/CLKARDCLK -> dut/total6_reg/DSP_A_B_DATA_INST/B[10] (0) |
| lut_fixed_p7 | 7 | 300 | 23.331 | 0.678 | 0.059 | 0.904 | yes | 376.6 | 34 | 91 | 5 | 1 | dut/addr2_reg_1/CLKARDCLK -> dut/total6_reg/DSP_A_B_DATA_INST/B[10] (0) |
| lut_fixed_p7 | 7 | 400 | 17.500 | 0.110 | 0.071 | 0.488 | yes | 418.4 | 34 | 91 | 5 | 1 | dut/addr2_reg_1/CLKARDCLK -> dut/total6_reg/DSP_A_B_DATA_INST/B[9] (0) |
| lut_fixed_p7 | 7 | 500 | 14.000 | -0.049 | 0.075 | 0.238 | NO | 488.0 | 49 | 109 | 5 | 1 | dut/v1_reg[25]/C -> dut/addr2_reg_1/ADDRARDADDR[4] (3) |
| lut_fixed_p7 | 7 | 600 | 11.669 | -0.405 | 0.063 | -0.042 | NO | 482.6 | 48 | 109 | 5 | 1 | dut/v1_reg[25]/C -> dut/addr2_reg_1/ADDRARDADDR[4] (3) |
| old_lut_32bp | 1 | 100 | 10.000 | -4.699 | 0.172 | 4.725 | NO | 68.0 | 2468 | 3105 | 0 | 2 | x_r_reg[14]/C -> y_out_reg[21]/D (43) |
| old_lut_32bp | 1 | 75 | 13.333 | -1.031 | 0.195 | 6.391 | NO | 69.6 | 2480 | 3105 | 0 | 2 | x_r_reg[0]/C -> y_out_reg[27]/D (44) |
| old_lut_32bp | 1 | 50 | 20.000 | 0.819 | 0.141 | 9.725 | yes | 52.1 | 2360 | 3105 | 0 | 2 | x_r_reg[1]/C -> y_out_reg[17]/D (48) |
