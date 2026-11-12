// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-11.
// iv_mul.v - pipelined signed fixed-point multiply, round half up, saturate.
//
//   o = sat_OW( floor(a*b / 2^SHIFT) + bit[SHIFT-1](a*b) )
//
// Stage map (latency = MPIPE + 3):
//   s0            : a_r, b_r <= a, b                      (DSP AREG/BREG)
//   s1..sMPIPE    : product pipeline, pp[0] <= a_r*b_r    (DSP MREG, PREG, cascade regs)
//   sMPIPE+1      : rnd <= (p >>> SHIFT) + p[SHIFT-1]     (narrow fabric add)
//   sMPIPE+2      : o   <= saturate(rnd) to OW bits
// Rounding uses floor + one bit instead of adding 2^(SHIFT-1) to the full product,
// so the carry chain is only (AW+BW-SHIFT+1) bits wide.
// No reset on the datapath, so Vivado can pack the registers into DSPs/SRLs.
`timescale 1ns / 1ps
module iv_mul #(
    parameter AW    = 18,
    parameter BW    = 18,
    parameter SHIFT = 16,   // must be >= 1
    parameter OW    = 18,
    parameter MPIPE = 2     // must be >= 1
) (
    input  wire                 clk,
    input  wire signed [AW-1:0] a,
    input  wire signed [BW-1:0] b,
    output reg  signed [OW-1:0] o
);
    localparam PW = AW + BW;
    localparam RW = PW - SHIFT + 1;   // rounded value width (one guard bit for the +1)

    (* use_dsp = "yes" *) reg signed [AW-1:0] a_r;
    (* use_dsp = "yes" *) reg signed [BW-1:0] b_r;
    reg signed [PW-1:0] pp [0:MPIPE-1];
    reg signed [RW-1:0] rnd;

    integer i;
    always @(posedge clk) begin
        a_r   <= a;
        b_r   <= b;
        pp[0] <= a_r * b_r;
        for (i = 1; i < MPIPE; i = i + 1)
            pp[i] <= pp[i-1];
        rnd   <= $signed(pp[MPIPE-1][PW-1:SHIFT]) + $signed({1'b0, pp[MPIPE-1][SHIFT-1]});
    end

    // saturate: the value fits OW bits when bits [RW-1:OW-1] are all equal
    wire all0 = ~|rnd[RW-1:OW-1];
    wire all1 =  &rnd[RW-1:OW-1];
    always @(posedge clk) begin
        if (all0 | all1) o <= rnd[OW-1:0];
        else if (rnd[RW-1]) o <= {1'b1, {(OW-1){1'b0}}};
        else                o <= {1'b0, {(OW-1){1'b1}}};
    end
endmodule
