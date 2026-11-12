// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-11.
// iv_defs.vh - shared constants for the ionic + voltage pipeline (rtl/ionic_voltage).
//
// Units: V in volts, g in nS, I in nA, C in nF, dt in s.
// cdt = dt / C_m, in V per nA. Then dV = cdt * I_total.
//
// Two fixed-point builds, picked by the W parameter (18 or 32).
// xF = number of fraction bits. Every word is W-bit two's complement unless it says otherwise.
//
//   field          W = 18                     W = 32
//   V, E, Vth      VF 18 (+-0.5 V, 3.8 uV)    VF 28 (Q4.28, +-8 V)
//   m, h           MF 16 (1.0 = 0x1_0000)     MF 31 (Q1.31 unsigned, 1.0 = 0x8000_0000)
//   gbar           GF  8 (+-512 nS)           GF 20 (Q12.20)
//   I (per ion)    IF 10 (+-128 nA)           IF 20 (Q12.20, +-2048 nA)
//   cdt            CF 27 (max 9.8e-4 V/nA)    CF 41 (max 9.8e-4 V/nA)
//   I_total        W+4 bits, IF fraction bits
//
// m and h are read as unsigned (MF+1) bits, and their values must be <= 1.0. The W = 18
// build uses MF = 16, so every operand fits one DSP48E2 port (27s x 18s).
// The W = 32 build uses MF = 31, so it accepts the gate core's Q1.31 outputs as they are.

`ifndef IV_DEFS_VH
`define IV_DEFS_VH

// ---- fixed-point formats (fraction bits), by datapath width -------------------
`define IV_VF(w)  ((w) == 18 ? 18 : 28)
`define IV_MF(w)  ((w) == 18 ? 16 : 31)
`define IV_GF(w)  ((w) == 18 ?  8 : 20)
`define IV_IF(w)  ((w) == 18 ? 10 : 20)
`define IV_CF(w)  ((w) == 18 ? 27 : 41)

// Extra multiplier pipeline registers, after the input register (AREG/BREG) and before
// rounding. 18-bit: MREG + PREG of one DSP48E2. 32-bit: the 4-DSP cascade needs more.
`define IV_MPIPE(w) ((w) == 18 ? 2 : 4)

// ---- model shape --------------------------------------------------------------
// 10 currents: Na, P, CaF, CaS, h, K1, K2, KA, KF, leak.
// 9 m gates  : Na, P, CaF, CaS, h, K1, K2, KA, KF.
// 5 h gates  : Na, CaF, CaS, K1, KA.
`define IV_N_ION   10
`define IV_N_M      9
`define IV_N_H      5
`define IV_SUM_GUARD 4          // I_total = W + 4 bits (up to 16 terms)

// Which gate feeds which current. Each entry is 4 bits, current 0 in the low nibble.
// 4'hF = none (the lane then uses 0; give it p = 0 / q = 0 so it multiplies by 1.0).
//                         leak KF  KA  K2  K1  h   CaS CaF P   Na
`define IV_M_SEL   40'hF_8_7_6_5_4_3_2_1_0
`define IV_H_SEL   40'hF_F_4_F_3_F_2_1_F_0

// Per-current exponent word PQ (3 bits): [1:0] p = m exponent (0..3), [2] q = h exponent (0/1).
`define IV_PQ_W     3

`endif
