// iv_ionic.v - Ionic Module: N_ION current lanes in parallel plus the I_total adder tree.
//
//   I_total = sum_i gbar_i m_i^p_i h_i^q_i (V - E_i)  +  I_syn  -  I_app
//
// Sign convention: currents are positive outward (I = g(V - E)), as in the block diagram.
// I_syn uses the same convention (g_syn (V - E_syn)). I_app is the injected current
// (positive depolarises), so it is subtracted.
//
// Stage map (LAT = LANE_LAT + TREE_LAT):
//   s0 .. LANE_LAT-1            : N_ION x iv_ion_lane; {I_syn, I_app} delayed LANE_LAT-1
//   LANE_LAT-1                  : isa = I_syn - I_app   (W+1 bits, last cycle of the lanes)
//   LANE_LAT .. LAT-1           : iv_add_tree over N_ION + 1 terms -> W + SUM_GUARD bits
`timescale 1ns / 1ps
`include "iv_defs.vh"
module iv_ionic #(
    parameter W     = 18,
    parameter N_ION = `IV_N_ION,
    parameter MPIPE = `IV_MPIPE(W)
) (
    input  wire                        clk,
    input  wire signed [W-1:0]         v,
    input  wire [N_ION*W-1:0]          m_cur,   // m for each current (already routed)
    input  wire [N_ION*W-1:0]          h_cur,   // h for each current
    input  wire [N_ION*W-1:0]          gbar,
    input  wire [N_ION*W-1:0]          e_rev,
    input  wire [N_ION*`IV_PQ_W-1:0]   pq,
    input  wire signed [W-1:0]         i_syn,
    input  wire signed [W-1:0]         i_app,
    output wire signed [W+`IV_SUM_GUARD-1:0] i_total
);
    localparam ML       = MPIPE + 3;
    localparam LANE_LAT = 1 + 3 * ML;
    localparam NT       = N_ION + 1;
    localparam TREE_LAT = (NT <= 1) ? 1 : $clog2(NT);
    localparam LAT      = LANE_LAT + TREE_LAT;
    localparam SW       = W + `IV_SUM_GUARD;
    localparam TW       = W + 1;                 // tree input word width

    wire [NT*TW-1:0] terms;

    genvar g;
    generate
        for (g = 0; g < N_ION; g = g + 1) begin : g_lane
            wire signed [W-1:0] i_g;
            iv_ion_lane #(.W(W), .MPIPE(MPIPE)) u_lane (
                .clk(clk), .v(v),
                .m(m_cur[g*W +: W]), .h(h_cur[g*W +: W]),
                .gbar(gbar[g*W +: W]), .e_rev(e_rev[g*W +: W]),
                .pq(pq[g*`IV_PQ_W +: `IV_PQ_W]),
                .i_out(i_g));
            assign terms[g*TW +: TW] = {i_g[W-1], i_g};
        end
    endgenerate

    // I_syn - I_app, ready on the same cycle as the lane outputs
    wire signed [W-1:0] syn_d, app_d;
    iv_dly #(.WD(2*W), .D(LANE_LAT-1)) u_sa (clk, {i_syn, i_app}, {syn_d, app_d});
    reg signed [W:0] isa_r;
    always @(posedge clk) isa_r <= {syn_d[W-1], syn_d} - {app_d[W-1], app_d};
    assign terms[N_ION*TW +: TW] = isa_r;

    iv_add_tree #(.N(NT), .WI(TW), .WO(SW)) u_tree (.clk(clk), .d(terms), .sum(i_total));
endmodule
