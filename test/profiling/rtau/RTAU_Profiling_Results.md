# 1/tau LUT profiling: 18 vs 32-bit, 128 vs 256 samples, block RAM vs distributed RAM

> AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-09.

KR260 chip (`xck26-sfvc784-2LV-c`), Vivado 2026.1. All results are from Vivado: out-of-context synthesis, place and route of the LUT, plus simulation of the RTL and of the routed netlist. **No board test**: the KR260 board failed on 2026-11-09 and the team decided simulation on the chip model is enough.

## What was simulated

**Function.** The time-constant reciprocal 1/tau(V) in 1/s, which the gate update needs (m' = m + dt * (1/tau) * (f_inf - m)). The table stores 1/tau itself, so the hardware has **no divide**. It is indexed by V, so a, b, c, d (or a_rec .. d_rec) are not used at run time; the table was computed offline in Python from the exact formulas in `Get Familiar/Hodgkin Huxley Equations.docx`.

| curve_sel | Curve | tau(V) (seconds, V in volts) |
|---|---|---|
| 0 | hNa | 0.004 + 0.006/(1+e^(500(V+0.028))) + 0.01/cosh(300(V+0.027)) |
| 1 | mP | 0.01 + 0.2/(1+e^(400(V+0.057))) |
| 2 | mCaF | 0.011 + 0.024/cosh(-330(V+0.0467)) |
| 3 | hCaF | 0.06 + 0.31/(1+e^(270(V+0.055))) |
| 4 | mCaS | 0.005 + 0.134/(1+e^(-400(V+0.0487))) |
| 5 | hCaS | 0.2 + 5.25/(1+e^(-250(V+0.043))) |
| 6 | mh | 0.7 + 1.7/(1+e^(-100(V+0.073))) |
| 7 | mK1 | 0.001 + 0.011/(1+e^(150(V+0.016))) |
| 8 | hK1 | 0.5 + 0.2/(1+e^(-143(V+0.013))) |

mNa has a constant tau of 0.0001 s (1/tau = 10,000 1/s), so it needs a constant, not a table. curve_sel 9-15 are empty.

**Real V range** (leech trace, dt = 0.03125 ms): -62.48 to +18.32 mV. 1/tau over it runs from 0.18 (hCaS) to 940 1/s (mK1).

**The 8 configurations** (team request, 2026-11-09):

| | Choices |
|---|---|
| Number size (ALL numbers: V, offset b, slope dy, output y) | 18-bit Q10.7 or 32-bit Q10.21 (1 sign + 10 integer + 7 or 21 fraction bits) |
| Samples (pieces) per curve | 128 (1 mV each) or 256 (0.5 mV each), over -64 .. +64 mV |
| Table memory | block RAM or distributed RAM (LUTs) |
| Pipeline stages tried | 4 and 6 (18-bit); 4, 6 and 7 (32-bit: the multiply needs two chained DSPs) |

**How the table is addressed (bit slicing)**, F = fraction bits (7 or 21):

```
u     = V + 64 mV  (= V + 2^(F+6)), clamped to 0 .. 2^(F+7)-1
256 samples: index = u[F+6 : F-1]  (8 bits)   frac = u[F-2 : 0]
128 samples: index = u[F+6 : F]    (7 bits)   frac = u[F-1 : 0]
address = {curve_sel[3:0], index};  word = {b, dy}  (2 x W bits)
y = b + dy * frac / 2^(frac bits),  rounded, clamped to 0 .. largest positive number
```

| Config | index | frac | Table | One lookup fetches |
|---|---|---|---|---|
| 18-bit, 128 samples | u[13:7] | u[6:0] | 2048 words x 36 bits | 1 word = 2 numbers (b, dy) |
| 18-bit, 256 samples | u[13:6] | u[5:0] | 4096 words x 36 bits | 1 word = 2 numbers (b, dy) |
| 32-bit, 128 samples | u[27:21] | u[20:0] | 2048 words x 64 bits | 1 word = 2 numbers (b, dy) |
| 32-bit, 256 samples | u[27:20] | u[19:0] | 4096 words x 64 bits | 1 word = 2 numbers (b, dy) |

**Tests.** Each design was checked bit for bit against the Python bit-exact model (`gen_rtau_cfg.py`): every piece edge, edge +-1 LSB, every piece middle, 2,000 random V in the real range and 200 anywhere, per curve, plus extreme values (24,520 inputs at 128 samples, 29,128 at 256).
- RTL (xsim): all 20 design x configuration combinations, 0 mismatches; measured latency = stage count.
- Gate level: the routed netlist of each configuration at its highest passing clock (table below).

## Definitions

- **Highest passing clock** = the sweep ran 600, 550, 500, 450, 400 MHz (in that order) and stopped at the first clock where setup (WNS), hold (WHS) and pulse width (WPWS) all pass. Below 400 MHz was not run.
- **x** = cycles - 1 (the f_inf/tau box in the neuron-core diagram is (1 + x); the first clock overlaps the step before the LUT).
- **Throughput:** every version takes one new input per clock (one lookup per clock per table copy).
- **Resources** are for the LUT only (the sweep's wrapper registers are not counted).

## Accuracy (bit-exact model = what the hardware computes; max relative error vs exact 1/tau, real V range)

| Config | hNa | mP | mCaF | hCaF | mCaS | hCaS | mh | mK1 | hK1 | Worst |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 18-bit, 128 samples | 0.349% | 0.543% | 0.446% | 0.296% | 0.523% | 3.309% | 1.653% | 0.057% | 0.609% | **3.31%** |
| 18-bit, 256 samples | 0.090% | 0.146% | 0.119% | 0.227% | 0.141% | 4.013% | 1.616% | 0.016% | 0.516% | **4.01%** |
| 32-bit, 128 samples | 0.357% | 0.533% | 0.464% | 0.123% | 0.594% | 0.221% | 0.008% | 0.055% | 0.005% | **0.594%** |
| 32-bit, 256 samples | 0.089% | 0.126% | 0.117% | 0.030% | 0.139% | 0.053% | 0.002% | 0.014% | 0.001% | **0.139%** |
| Old 32-point tau table (stores tau, needs a divide) | 1.975% | 1.190% | 0.573% | 0.310% | 1.577% | 1.265% | 0.058% | 0.670% | 0.026% | 1.975% |

## Highest passing clock per configuration

| Bits | Samples | Memory | Stages | Cycles (x) | Highest passing clock | Latency there | WNS / WPWS there (ns) | LUT | FF | BRAM tiles | DSP | Gate-level sim |
|---:|---:|---|---:|---|---|---:|---|---:|---:|---:|---:|---|
| 18 | 128 | bram | 4 | 4 (3) | **400 MHz** | 10.00 ns | 0.053 / 0.488 | 27 | 20 | 2 | 1 | PASS (0 errors) |
| 18 | 128 | bram | 6 | 6 (5) | **400 MHz** | 15.00 ns | 0.079 / 0.488 | 28 | 63 | 2 | 1 | PASS (0 errors) |
| 18 | 128 | dist | 4 | 4 (3) | **400 MHz** | 10.00 ns | 0.120 / 0.488 | 369 | 73 | 0 | 1 | PASS (0 errors) |
| 18 | 128 | dist | 6 | 6 (5) | **600 MHz** | 10.00 ns | 0.033 / 0.072 | 382 | 115 | 0 | 1 | PASS (0 errors) |
| 18 | 256 | bram | 4 | 4 (3) | **400 MHz** | 10.00 ns | 0.059 / 0.488 | 34 | 40 | 4 | 1 | PASS (0 errors) |
| 18 | 256 | bram | 6 | 6 (5) | **400 MHz** | 15.00 ns | 0.034 / 0.488 | 34 | 62 | 4 | 1 | PASS (0 errors) |
| 18 | 256 | dist | 4 | 4 (3) | **400 MHz** | 10.00 ns | 0.149 / 0.488 | 509 | 79 | 0 | 1 | PASS (0 errors) |
| 18 | 256 | dist | 6 | 6 (5) | **550 MHz** | 10.91 ns | 0.069 / 0.147 | 530 | 121 | 0 | 1 | PASS (0 errors) |
| 32 | 128 | bram | 4 | 4 (3) | none >= 400 MHz | | -0.391 / 0.488 at 400 | 103 | 121 | 4 | 2 | |
| 32 | 128 | bram | 6 | 6 (5) | none >= 400 MHz | | -0.391 / 0.488 at 400 | 99 | 192 | 4 | 2 | |
| 32 | 128 | bram | 7 | 7 (6) | none >= 400 MHz | | -0.391 / 0.488 at 400 | 97 | 255 | 4 | 2 | |
| 32 | 128 | dist | 4 | 4 (3) | none >= 400 MHz | | -0.391 / 0.488 at 400 | 979 | 190 | 0 | 2 | |
| 32 | 128 | dist | 6 | 6 (5) | none >= 400 MHz | | -0.391 / 0.488 at 400 | 981 | 261 | 0 | 2 | |
| 32 | 128 | dist | 7 | 7 (6) | none >= 400 MHz | | -0.391 / 0.488 at 400 | 986 | 299 | 0 | 2 | |
| 32 | 256 | bram | 4 | 4 (3) | none >= 400 MHz | | -0.637 / 0.488 at 400 | 207 | 144 | 7 | 1 | |
| 32 | 256 | bram | 6 | 6 (5) | none >= 400 MHz | | -0.629 / 0.488 at 400 | 203 | 215 | 7 | 1 | |
| 32 | 256 | bram | 7 | 7 (6) | none >= 400 MHz | | -0.637 / 0.488 at 400 | 199 | 277 | 7 | 1 | |
| 32 | 256 | dist | 4 | 4 (3) | none >= 400 MHz | | -0.647 / 0.488 at 400 | 2267 | 272 | 0 | 1 | |
| 32 | 256 | dist | 6 | 6 (5) | none >= 400 MHz | | -0.665 / 0.488 at 400 | 2271 | 343 | 0 | 1 | |
| 32 | 256 | dist | 7 | 7 (6) | none >= 400 MHz | | -0.635 / 0.488 at 400 | 2285 | 386 | 0 | 1 | |

Old LUT for comparison (f_inf sweep, 2026-11-02; same hardware whatever table it holds): 1 clock, passes 50 MHz (fails 75), 2,468 LUTs, 3,105 FFs, 2 DSPs, and it stores tau, so 1/tau would also need a divider.

## Findings

- **18-bit, 6 stages, distributed RAM is the fastest 1/tau LUT: 600 MHz at 128 samples** (WNS +0.033 ns, WPWS +0.072 ns), and 550 MHz at 256 samples. It is the first version of either LUT (f_inf or 1/tau) to pass 600 MHz, because distributed RAM does not have the block RAM's 1.709 ns minimum period. The 600 MHz margin is thin, so plan 550 MHz if the full neuron core is crowded.
- **18-bit with block RAM, or with only 4 stages, stops at 400 MHz.** It misses 450 MHz by 0.05-0.21 ns.
  - Block RAM: the slowest path is the address calculation (add 64 mV + clamp) feeding the RAM's address pins, and 600 MHz also fails the RAM's pulse width (WPWS -0.042 ns).
  - Distributed RAM at 4 stages: the slowest path is the final add/round in the DSP. The 2 extra stages split that up, which is what lets 6 stages reach 600 MHz.
- **No 32-bit configuration reaches 400 MHz**, with either memory type, at 4, 6 or 7 stages (WNS at 400 MHz: about -0.39 ns at 128 samples, -0.63 to -0.67 ns at 256).
  - The cause is the 32 x 21 multiply. Vivado built it from 1-2 DSPs plus about 10 levels of LUT adders, all in one clock.
  - The extra register in the 7-stage version was not pulled into the DSPs (MREG = PREG = 0), so 7 stages are no faster than 6.
  - Fix, not tried yet: split the multiply into two explicit 27 x 18 partial products with a register between them, or use AMD's Multiplier IP (mult_gen) with its pipeline stages set.
- **Accuracy is set by the number size.**
  - 32-bit: rounding is negligible, so the sample count decides. 256 samples gives 0.14%, which beats every old 32-point tau table on every curve. 128 samples gives 0.59%.
  - 18-bit (Q10.7): the 7 fraction bits limit it to 3.3% (128 samples) or 4.0% (256), worse than the old tables on hCaS, mh and hK1. More samples make 18-bit slightly worse, because each piece's slope becomes a smaller number.
- **Resources are small.**
  - Block RAM: 18-bit uses 2 tiles (128 samples) or 4 (256); 32-bit uses 4 or 7.
  - Distributed RAM: 18-bit uses 369-382 LUTs (128 samples) or 509-530 (256); 32-bit uses about 1,000 (128) or 2,300-2,550 (256). Vivado built these tables as ROMs from logic LUTs ("LUT as Memory" = 0), and compressed them below the raw bit count.
  - Every configuration uses 1-2 DSPs.
  - The old LUT used 2,468 LUTs and 3,105 FFs, and ran at 50 MHz.
- **Storage (18-bit, 128 samples):** 2 numbers per piece (offset and slope, 18 bits each; no x is stored, because the address is x). That is 4,608 bits (576 bytes) per curve and 41,472 bits (5,184 bytes) for 9 curves. As built, the table reserves 16 curve slots (2,048 x 36 bits = 2 block RAM tiles).

## Recommendations

- **For the highest clock: 18-bit, 6 stages, distributed RAM, 128 samples at 600 MHz** (6 cycles = 10 ns, x = 5, 382 LUTs, no block RAM). Its margin is +0.033 ns, so use 550 MHz if the full core is crowded. 128 samples is also the more accurate 18-bit option (3.3% vs 4.0%).
  - Check that 3.3% is acceptable for the gate update: it is worse than the old tau tables on hCaS, mh and hK1.
  - Distributed RAM also allows many parallel reads (one small table per gate). That design is built and passes RTL simulation; its timing sweep has not run yet.
- **If accuracy matters more:** 32-bit, 256 samples (0.14%). It needs the multiply fix above before it closes 400 MHz. Until then its speed is unknown, because the sweep stopped at 400 MHz.
- **Next steps:**
  - Pipelined 32-bit multiply (two DSPs, a register between them).
  - Per-curve scaling for 18-bit (0.14% at 256 samples, measured in Python) instead of one shared Q10.7 format.
  - The 9-gate parallel-read timing sweep.

## Every run

| Config | Stages | MHz | WNS | WHS | WPWS | Met | Est. Fmax (setup only) | LUT | LUT as mem | FF | BRAM | DSP | DSP regs | Slowest path (levels) |
|---|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---|---|
| 18-bit 128 bram | 4 | 600 | -0.628 | 0.089 | -0.042 | NO | 435.7 | 41 | 1 | 41 | 2 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | v_r_reg[12]/C -> dut/addr2_reg_1/ADDRARDADDR[4] (4) |
| 18-bit 128 bram | 4 | 550 | -0.585 | 0.089 | 0.109 | NO | 416.1 | 42 | 1 | 41 | 2 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | v_r_reg[14]/C -> dut/addr2_reg_1/ADDRARDADDR[4] (4) |
| 18-bit 128 bram | 4 | 500 | -0.359 | 0.085 | 0.238 | NO | 423.9 | 41 | 1 | 41 | 2 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | v_r_reg[15]/C -> dut/addr2_reg_1/ADDRARDADDR[4] (4) |
| 18-bit 128 bram | 4 | 450 | -0.156 | 0.089 | 0.349 | NO | 420.5 | 42 | 1 | 41 | 2 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/rounded/DSP_M_DATA_INST/CLK -> dut/y_out_reg[4]/D (5) |
| 18-bit 128 bram | 4 | 400 | 0.053 | 0.104 | 0.488 | yes | 408.7 | 27 | 1 | 20 | 2 | 1 | AREG=1 BREG=2 CREG=0 MREG=0 PREG=1; | dut/addr2_reg_0/CLKARDCLK -> dut/rounded/DSP_A_B_DATA_INST/A[14] (0) |
| 18-bit 128 bram | 6 | 600 | -0.658 | 0.064 | -0.042 | NO | 430.1 | 42 | 1 | 63 | 2 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=1; | dut/v1_reg[12]/C -> dut/addr2_reg_1/ADDRARDADDR[4] (4) |
| 18-bit 128 bram | 6 | 550 | -0.508 | 0.064 | 0.109 | NO | 429.9 | 42 | 1 | 63 | 2 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=1; | dut/v1_reg[12]/C -> dut/addr2_reg_1/ADDRARDADDR[4] (4) |
| 18-bit 128 bram | 6 | 500 | -0.300 | 0.064 | 0.238 | NO | 434.8 | 42 | 1 | 63 | 2 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=1; | dut/v1_reg[12]/C -> dut/addr2_reg_1/ADDRARDADDR[4] (4) |
| 18-bit 128 bram | 6 | 450 | -0.181 | 0.064 | 0.349 | NO | 416.1 | 42 | 1 | 83 | 2 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/v1_reg[12]/C -> dut/addr2_reg_1/ADDRARDADDR[4] (4) |
| 18-bit 128 bram | 6 | 400 | 0.079 | 0.064 | 0.488 | yes | 413.1 | 28 | 1 | 63 | 2 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=1; | dut/v1_reg[13]/C -> dut/addr2_reg_0/ADDRARDADDR[4] (5) |
| 18-bit 128 dist | 4 | 600 | -0.643 | 0.063 | 0.072 | NO | 432.9 | 378 | 1 | 73 | 0 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/rounded/DSP_M_DATA_INST/CLK -> dut/y_out_reg[5]/D (5) |
| 18-bit 128 dist | 4 | 550 | -0.480 | 0.100 | 0.147 | NO | 435.2 | 380 | 1 | 73 | 0 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/rounded/DSP_M_DATA_INST/CLK -> dut/y_out_reg[4]/D (5) |
| 18-bit 128 dist | 4 | 500 | -0.293 | 0.093 | 0.238 | NO | 436.1 | 379 | 1 | 73 | 0 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/rounded/DSP_M_DATA_INST/CLK -> dut/y_out_reg[8]/D (5) |
| 18-bit 128 dist | 4 | 450 | -0.053 | 0.089 | 0.349 | NO | 439.6 | 380 | 1 | 73 | 0 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/rounded/DSP_M_DATA_INST/CLK -> dut/y_out_reg[10]/D (5) |
| 18-bit 128 dist | 4 | 400 | 0.120 | 0.085 | 0.488 | yes | 420.2 | 369 | 1 | 73 | 0 | 1 | AREG=0 BREG=1 CREG=0 MREG=0 PREG=1; | dut/rounded_i_8_psdsp/C -> dut/rounded/DSP_OUTPUT_INST/ALU_OUT[21] (5) |
| 18-bit 128 dist | 6 | 600 | 0.033 | 0.063 | 0.072 | yes | 612.0 | 382 | 1 | 115 | 0 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/v1_reg[15]/C -> dut/addr2_reg[4]/D (4) |
| 18-bit 256 bram | 4 | 600 | -0.781 | 0.089 | -0.042 | NO | 408.5 | 43 | 1 | 40 | 4 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | v_r_reg[15]/C -> dut/addr2_reg_1/ADDRARDADDR[4] (4) |
| 18-bit 256 bram | 4 | 550 | -0.714 | 0.089 | 0.109 | NO | 394.9 | 40 | 1 | 40 | 4 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | v_r_reg[13]/C -> dut/addr2_reg_1/ADDRARDADDR[3] (4) |
| 18-bit 256 bram | 4 | 500 | -0.478 | 0.088 | 0.238 | NO | 403.6 | 39 | 1 | 40 | 4 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | v_r_reg[12]/C -> dut/addr2_reg_1/ADDRARDADDR[5] (4) |
| 18-bit 256 bram | 4 | 450 | -0.161 | 0.089 | 0.349 | NO | 419.6 | 42 | 1 | 40 | 4 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | v_r_reg[12]/C -> dut/addr2_reg_2/ADDRARDADDR[4] (4) |
| 18-bit 256 bram | 4 | 400 | 0.059 | 0.102 | 0.488 | yes | 409.7 | 34 | 1 | 40 | 4 | 1 | AREG=0 BREG=1 CREG=0 MREG=0 PREG=1; | v_r_reg[12]/C -> dut/addr2_reg_1/ADDRARDADDR[4] (4) |
| 18-bit 256 bram | 6 | 600 | -0.728 | 0.064 | -0.042 | NO | 417.5 | 40 | 1 | 82 | 4 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/v1_reg[12]/C -> dut/addr2_reg_3/ADDRARDADDR[4] (4) |
| 18-bit 256 bram | 6 | 550 | -0.701 | 0.075 | 0.109 | NO | 397.0 | 44 | 1 | 82 | 4 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/v1_reg[15]/C -> dut/addr2_reg_2/ADDRARDADDR[3] (4) |
| 18-bit 256 bram | 6 | 500 | -0.456 | 0.071 | 0.238 | NO | 407.2 | 44 | 1 | 82 | 4 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/v1_reg[12]/C -> dut/addr2_reg_1/ADDRARDADDR[3] (4) |
| 18-bit 256 bram | 6 | 450 | -0.209 | 0.064 | 0.349 | NO | 411.4 | 43 | 1 | 62 | 4 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=1; | dut/v1_reg[12]/C -> dut/addr2_reg_3/ADDRARDADDR[3] (4) |
| 18-bit 256 bram | 6 | 400 | 0.034 | 0.064 | 0.488 | yes | 405.5 | 34 | 1 | 62 | 4 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=1; | dut/v1_reg[15]/C -> dut/addr2_reg_2/ADDRARDADDR[4] (4) |
| 18-bit 256 dist | 4 | 600 | -0.625 | 0.093 | 0.072 | NO | 436.3 | 900 | 1 | 95 | 0 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/rounded/DSP_M_DATA_INST/CLK -> dut/y_out_reg[4]/D (5) |
| 18-bit 256 dist | 4 | 550 | -0.448 | 0.071 | 0.147 | NO | 441.3 | 525 | 1 | 79 | 0 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/rounded/DSP_M_DATA_INST/CLK -> dut/y_out_reg[15]/D (5) |
| 18-bit 256 dist | 4 | 500 | -0.305 | 0.091 | 0.238 | NO | 433.8 | 523 | 1 | 79 | 0 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/rounded/DSP_M_DATA_INST/CLK -> dut/y_out_reg[13]/D (5) |
| 18-bit 256 dist | 4 | 450 | -0.079 | 0.099 | 0.349 | NO | 434.6 | 516 | 1 | 79 | 0 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/rounded/DSP_M_DATA_INST/CLK -> dut/y_out_reg[5]/D (5) |
| 18-bit 256 dist | 4 | 400 | 0.149 | 0.085 | 0.488 | yes | 425.4 | 509 | 1 | 79 | 0 | 1 | AREG=0 BREG=1 CREG=0 MREG=0 PREG=1; | dut/rounded_i_7_psdsp/C -> dut/rounded/DSP_OUTPUT_INST/ALU_OUT[27] (5) |
| 18-bit 256 dist | 6 | 600 | -0.118 | 0.064 | 0.072 | NO | 560.2 | 902 | 1 | 117 | 0 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=1; | dut/addr2_reg[3]_rep__0/C -> dut/g_dist.word3_reg[13]/D (5) |
| 18-bit 256 dist | 6 | 550 | 0.069 | 0.063 | 0.147 | yes | 571.8 | 530 | 1 | 121 | 0 | 1 | AREG=0 BREG=1 CREG=1 MREG=1 PREG=0; | dut/addr2_reg[2]/C -> dut/g_dist.word3_reg[17]/D (5) |
| 32-bit 128 bram | 4 | 600 | -1.224 | 0.091 | -0.042 | NO | 345.9 | 108 | 1 | 121 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 4 | 550 | -1.073 | 0.094 | 0.109 | NO | 345.9 | 106 | 1 | 121 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 4 | 500 | -0.910 | 0.088 | 0.238 | NO | 343.6 | 108 | 1 | 121 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40__0/DSP_OUTPUT_INST/CLK -> dut/y_out_reg[31]/R (9) |
| 32-bit 128 bram | 4 | 450 | -0.669 | 0.086 | 0.349 | NO | 345.9 | 104 | 1 | 110 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=1 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 4 | 400 | -0.391 | 0.104 | 0.488 | NO | 345.9 | 103 | 1 | 121 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 6 | 600 | -1.224 | 0.071 | -0.042 | NO | 345.9 | 105 | 1 | 192 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 6 | 550 | -1.073 | 0.064 | 0.109 | NO | 345.9 | 103 | 1 | 192 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 6 | 500 | -0.891 | 0.064 | 0.238 | NO | 345.9 | 106 | 1 | 192 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 6 | 450 | -0.669 | 0.075 | 0.349 | NO | 345.9 | 109 | 1 | 192 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 6 | 400 | -0.391 | 0.064 | 0.488 | NO | 345.9 | 99 | 1 | 192 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 7 | 600 | -1.224 | 0.059 | -0.042 | NO | 345.9 | 107 | 1 | 255 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 7 | 550 | -1.073 | 0.059 | 0.109 | NO | 345.9 | 104 | 1 | 255 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 7 | 500 | -0.891 | 0.059 | 0.238 | NO | 345.9 | 109 | 1 | 255 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 7 | 450 | -0.669 | 0.059 | 0.349 | NO | 345.9 | 105 | 1 | 255 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 bram | 7 | 400 | -0.391 | 0.059 | 0.488 | NO | 345.9 | 97 | 1 | 255 | 4 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 4 | 600 | -1.224 | 0.077 | 0.072 | NO | 345.9 | 991 | 1 | 194 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 4 | 550 | -1.073 | 0.080 | 0.147 | NO | 345.9 | 994 | 1 | 190 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 4 | 500 | -0.891 | 0.073 | 0.238 | NO | 345.9 | 987 | 1 | 190 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 4 | 450 | -0.683 | 0.089 | 0.349 | NO | 344.2 | 986 | 1 | 190 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40__0/DSP_OUTPUT_INST/CLK -> dut/y_out_reg[31]/R (10) |
| 32-bit 128 dist | 4 | 400 | -0.391 | 0.088 | 0.488 | NO | 345.9 | 979 | 1 | 190 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 6 | 600 | -1.224 | 0.064 | 0.072 | NO | 345.9 | 996 | 1 | 265 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 6 | 550 | -1.073 | 0.059 | 0.147 | NO | 345.9 | 987 | 1 | 261 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 6 | 500 | -0.891 | 0.071 | 0.238 | NO | 345.9 | 987 | 1 | 261 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 6 | 450 | -0.669 | 0.059 | 0.349 | NO | 345.9 | 982 | 1 | 261 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 6 | 400 | -0.391 | 0.075 | 0.488 | NO | 345.9 | 981 | 1 | 261 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod40__0/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 7 | 600 | -1.224 | 0.071 | 0.072 | NO | 345.9 | 1014 | 15 | 295 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 7 | 550 | -1.073 | 0.064 | 0.147 | NO | 345.9 | 1002 | 10 | 297 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 7 | 500 | -0.891 | 0.063 | 0.238 | NO | 345.9 | 1004 | 10 | 287 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=1 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 7 | 450 | -0.669 | 0.064 | 0.349 | NO | 345.9 | 990 | 10 | 301 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 128 dist | 7 | 400 | -0.391 | 0.063 | 0.488 | NO | 345.9 | 986 | 10 | 299 | 0 | 2 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; AREG=1 BREG=0 CREG=1 MREG=0 PREG=1; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg/DSP_OUTPUT_INST/ALU_OUT[0] (6) |
| 32-bit 256 bram | 4 | 600 | -1.450 | 0.085 | -0.042 | NO | 320.8 | 215 | 1 | 144 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 bram | 4 | 550 | -1.304 | 0.085 | 0.109 | NO | 320.3 | 216 | 1 | 144 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 bram | 4 | 500 | -1.079 | 0.091 | 0.238 | NO | 324.8 | 215 | 1 | 144 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 bram | 4 | 450 | -0.923 | 0.085 | 0.349 | NO | 318.0 | 211 | 1 | 144 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 bram | 4 | 400 | -0.637 | 0.089 | 0.488 | NO | 318.8 | 207 | 1 | 144 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 bram | 6 | 600 | -1.418 | 0.063 | -0.042 | NO | 324.1 | 210 | 1 | 215 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 bram | 6 | 550 | -1.319 | 0.063 | 0.109 | NO | 318.8 | 211 | 1 | 215 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 bram | 6 | 500 | -1.145 | 0.064 | 0.238 | NO | 318.0 | 212 | 1 | 215 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 bram | 6 | 450 | -0.915 | 0.075 | 0.349 | NO | 318.8 | 214 | 1 | 215 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 bram | 6 | 400 | -0.629 | 0.064 | 0.488 | NO | 319.6 | 203 | 1 | 215 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 bram | 7 | 600 | -1.470 | 0.060 | -0.042 | NO | 318.8 | 216 | 1 | 277 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[29]/D (10) |
| 32-bit 256 bram | 7 | 550 | -1.325 | 0.075 | 0.109 | NO | 318.2 | 216 | 1 | 277 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[29]/D (10) |
| 32-bit 256 bram | 7 | 500 | -1.132 | 0.063 | 0.238 | NO | 319.3 | 213 | 1 | 277 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[29]/D (10) |
| 32-bit 256 bram | 7 | 450 | -0.930 | 0.064 | 0.349 | NO | 317.3 | 207 | 1 | 277 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[29]/D (10) |
| 32-bit 256 bram | 7 | 400 | -0.637 | 0.059 | 0.488 | NO | 318.8 | 199 | 1 | 277 | 7 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[29]/D (10) |
| 32-bit 256 dist | 4 | 600 | -1.489 | 0.093 | 0.072 | NO | 316.9 | 2548 | 1 | 285 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 dist | 4 | 550 | -1.325 | 0.068 | 0.147 | NO | 318.2 | 2304 | 1 | 272 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 dist | 4 | 500 | -1.141 | 0.063 | 0.238 | NO | 318.4 | 2305 | 1 | 272 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 dist | 4 | 450 | -0.912 | 0.072 | 0.349 | NO | 319.1 | 2293 | 1 | 272 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 dist | 4 | 400 | -0.647 | 0.075 | 0.488 | NO | 317.8 | 2267 | 1 | 272 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 dist | 6 | 600 | -1.554 | 0.071 | 0.072 | NO | 310.5 | 2554 | 1 | 358 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/g_dist.word3_reg[3]/C -> dut/prod4_reg[47]/D (9) |
| 32-bit 256 dist | 6 | 550 | -1.352 | 0.071 | 0.147 | NO | 315.5 | 2303 | 1 | 343 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 dist | 6 | 500 | -1.155 | 0.063 | 0.238 | NO | 317.0 | 2300 | 1 | 343 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 dist | 6 | 450 | -0.881 | 0.071 | 0.349 | NO | 322.3 | 2291 | 1 | 343 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 dist | 6 | 400 | -0.665 | 0.070 | 0.488 | NO | 316.0 | 2271 | 1 | 343 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[46]/D (10) |
| 32-bit 256 dist | 7 | 600 | -1.470 | 0.063 | 0.072 | NO | 318.8 | 2561 | 18 | 391 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[29]/D (10) |
| 32-bit 256 dist | 7 | 550 | -1.321 | 0.064 | 0.147 | NO | 318.6 | 2317 | 13 | 384 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[29]/D (10) |
| 32-bit 256 dist | 7 | 500 | -1.163 | 0.085 | 0.238 | NO | 316.2 | 2318 | 13 | 383 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[29]/D (10) |
| 32-bit 256 dist | 7 | 450 | -0.942 | 0.063 | 0.349 | NO | 316.1 | 2313 | 13 | 384 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[29]/D (10) |
| 32-bit 256 dist | 7 | 400 | -0.635 | 0.064 | 0.488 | NO | 319.0 | 2285 | 13 | 386 | 0 | 1 | AREG=1 BREG=1 CREG=1 MREG=0 PREG=0; | dut/prod40/DSP_A_B_DATA_INST/CLK -> dut/prod4_reg[29]/D (10) |

## Files

- Model: `model/gen_rtau_cfg.py` (bit-exact model, tables, test vectors), `model/rtau_study.py` (curves, piece-width study), `model/uniform_format_study.py`, `model/make_rtau_report.py` (this report)
- RTL: `rtl/rtau_lut_s4.v`, `rtl/rtau_lut_s6.v`, `rtl/rtau_lut_s7.v` (parameters W, NB_LOG2, RAM_BLOCK), `rtl/rtau_cfg_top.v` (sweep wrapper), `rtl/rtau_w*_n*.mem` (tables)
- Sim: `sim/tb_rtau_cfg.v`, `sim/run_sim.bat`, `sim/run_funcsim.bat`; sweep: `scripts/run_cfg_sweep.tcl`, `reports/cfg_*.csv`, `reports/funcsim_results.txt`
