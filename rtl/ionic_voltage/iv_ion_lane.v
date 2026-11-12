// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-11.
// iv_ion_lane.v - one ionic current, one neuron per clock.
//
//   I = gbar * m^p * h^q * (V - E)        p in 0..3, q in 0..1 (from the PQ word, by data)
//
// Stage map (ML = MPIPE + 3 = latency of one iv_mul; LAT = 1 + 3*ML):
//   s0              : dv = V - E (W+1 bits); s1 = p[0] ? m : 1.0; hq = q ? h : 1.0
//   s1    .. ML     : L1  m2 = m*m          mh = s1*hq          gd = gbar*dv
//   ML+1  .. 2ML    : L2  x  = s2*mh        (s2 = p[1] ? m2 : 1.0)       gd delayed
//   2ML+1 .. 3ML    : L3  I  = x*gd
// Each multiply rounds half up and saturates (iv_mul). Mirrors iv_model.lane().
`timescale 1ns / 1ps
`include "iv_defs.vh"
module iv_ion_lane #(
    parameter W     = 18,
    parameter MPIPE = `IV_MPIPE(W)
) (
    input  wire                      clk,
    input  wire signed [W-1:0]       v,
    input  wire        [W-1:0]       m,      // unsigned, low MF+1 bits used, <= 1.0
    input  wire        [W-1:0]       h,
    input  wire signed [W-1:0]       gbar,
    input  wire signed [W-1:0]       e_rev,
    input  wire [`IV_PQ_W-1:0]       pq,     // [1:0] p, [2] q
    output wire signed [W-1:0]       i_out
);
    localparam VF = `IV_VF(W);
    localparam MF = `IV_MF(W);
    localparam GF = `IV_GF(W);
    localparam IF = `IV_IF(W);
    localparam MW = MF + 2;                       // signed width of m/h operands
    localparam ML = MPIPE + 3;
    localparam LAT = 1 + 3 * ML;
    localparam [MW-1:0] ONE = {{(MW-MF-1){1'b0}}, 1'b1, {MF{1'b0}}};

    // ---- s0 ----------------------------------------------------------------
    wire [MW-1:0] m_x = {1'b0, m[MF:0]};
    wire [MW-1:0] h_x = {1'b0, h[MF:0]};
    reg  signed [W:0]    dv_r;
    reg  signed [W-1:0]  gbar_r;
    reg  signed [MW-1:0] m_r, s1_r, hq_r;
    reg                  p1_r;
    always @(posedge clk) begin
        dv_r   <= {v[W-1], v} - {e_rev[W-1], e_rev};
        gbar_r <= gbar;
        m_r    <= m_x;
        s1_r   <= pq[0] ? m_x : ONE;
        hq_r   <= pq[2] ? h_x : ONE;
        p1_r   <= pq[1];
    end

    // ---- L1 ----------------------------------------------------------------
    wire signed [MW-1:0] m2, mh;
    wire signed [W-1:0]  gd;
    iv_mul #(.AW(MW), .BW(MW),  .SHIFT(MF),         .OW(MW), .MPIPE(MPIPE)) u_m2 (clk, m_r,    m_r,  m2);
    iv_mul #(.AW(MW), .BW(MW),  .SHIFT(MF),         .OW(MW), .MPIPE(MPIPE)) u_mh (clk, s1_r,   hq_r, mh);
    iv_mul #(.AW(W),  .BW(W+1), .SHIFT(GF+VF-IF),   .OW(W),  .MPIPE(MPIPE)) u_gd (clk, gbar_r, dv_r, gd);

    wire p1_d;
    iv_dly #(.WD(1), .D(ML)) u_p1 (clk, p1_r, p1_d);

    // ---- L2 ----------------------------------------------------------------
    wire signed [MW-1:0] s2 = p1_d ? m2 : ONE;
    wire signed [MW-1:0] x;
    wire signed [W-1:0]  gd_d;
    iv_mul #(.AW(MW), .BW(MW), .SHIFT(MF), .OW(MW), .MPIPE(MPIPE)) u_x (clk, s2, mh, x);
    iv_dly #(.WD(W), .D(ML)) u_gd_dly (clk, gd, gd_d);

    // ---- L3 ----------------------------------------------------------------
    iv_mul #(.AW(MW), .BW(W), .SHIFT(MF), .OW(W), .MPIPE(MPIPE)) u_i (clk, x, gd_d, i_out);
endmodule
