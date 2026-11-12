// iv_core.v - Ionic Module + Voltage Module, one neuron per clock, fully pipelined.
//
// Takes one neuron per clock: its V, its gate states (m, h) and its per-neuron constants
// (gbar, E, PQ, cdt, Vth), plus I_syn and I_app. Returns V', spike and I_total LAT
// clocks later, in order, with the same tag. A timestep is n_active + LAT cycles when V'
// feeds the next step's V.
//
// Stage map:
//   0              .. ION_LAT-1  : iv_ionic   (lanes 1 + 3*ML, then the adder tree)
//   ION_LAT        .. LAT-1      : iv_voltage (ML + 3)
//   V, cdt, Vth are delayed ION_LAT to meet I_total. valid and tag are delayed LAT.
//   ML = MPIPE + 3.  W=18: LAT = 16 + 4 + 8 = 28.  W=32: LAT = 22 + 4 + 10 = 36.
//
// Gate-to-current routing is set by `IV_M_SEL / `IV_H_SEL (iv_defs.vh). Exponents come
// from the PQ words (data), not from the lane index.
`timescale 1ns / 1ps
`include "iv_defs.vh"
module iv_core #(
    parameter W     = 18,           // 18 or 32
    parameter MPIPE = `IV_MPIPE(W),
    parameter TAGW  = 12            // neuron index, carried through for write-back
) (
    input  wire                              clk,
    input  wire                              rst,      // sync, clears valid only
    // ---- one neuron in ----
    input  wire                              in_valid,
    input  wire [TAGW-1:0]                   in_tag,
    input  wire signed [W-1:0]               v_in,
    input  wire [`IV_N_M*W-1:0]              m_in,     // gate m_k at [k*W +: W]
    input  wire [`IV_N_H*W-1:0]              h_in,
    input  wire signed [W-1:0]               i_syn,
    input  wire signed [W-1:0]               i_app,
    input  wire [`IV_N_ION*W-1:0]            gbar,
    input  wire [`IV_N_ION*W-1:0]            e_rev,
    input  wire [`IV_N_ION*`IV_PQ_W-1:0]     pq,
    input  wire signed [W-1:0]               cdt,
    input  wire signed [W-1:0]               vth,
    // ---- result out ----
    output wire                              out_valid,
    output wire [TAGW-1:0]                   out_tag,
    output wire signed [W-1:0]               v_out,
    output wire                              spike,
    output wire                              above,
    output wire signed [W+`IV_SUM_GUARD-1:0] i_total
);
    localparam N_ION    = `IV_N_ION;
    localparam ML       = MPIPE + 3;
    localparam NT       = N_ION + 1;
    localparam ION_LAT  = 1 + 3 * ML + $clog2(NT);
    localparam VOLT_LAT = ML + 3;
    localparam LAT      = ION_LAT + VOLT_LAT;
    localparam SW       = W + `IV_SUM_GUARD;
    localparam [4*N_ION-1:0] M_SEL = `IV_M_SEL;
    localparam [4*N_ION-1:0] H_SEL = `IV_H_SEL;

    // ---- gate -> current routing (wiring only) ----
    wire [N_ION*W-1:0] m_cur, h_cur;
    genvar g;
    generate
        for (g = 0; g < N_ION; g = g + 1) begin : g_route
            localparam [3:0] MS = M_SEL[4*g +: 4];
            localparam [3:0] HS = H_SEL[4*g +: 4];
            if (MS < `IV_N_M) begin : g_m  assign m_cur[g*W +: W] = m_in[MS*W +: W]; end
            else              begin : g_m0 assign m_cur[g*W +: W] = {W{1'b0}};       end
            if (HS < `IV_N_H) begin : g_h  assign h_cur[g*W +: W] = h_in[HS*W +: W]; end
            else              begin : g_h0 assign h_cur[g*W +: W] = {W{1'b0}};       end
        end
    endgenerate

    // ---- ionic module ----
    wire signed [SW-1:0] itot;
    iv_ionic #(.W(W), .N_ION(N_ION), .MPIPE(MPIPE)) u_ionic (
        .clk(clk), .v(v_in), .m_cur(m_cur), .h_cur(h_cur),
        .gbar(gbar), .e_rev(e_rev), .pq(pq), .i_syn(i_syn), .i_app(i_app),
        .i_total(itot));

    // ---- voltage module ----
    wire signed [W-1:0] v_d, cdt_d, vth_d;
    iv_dly #(.WD(3*W), .D(ION_LAT)) u_vcv (clk, {v_in, cdt, vth}, {v_d, cdt_d, vth_d});

    iv_voltage #(.W(W), .MPIPE(MPIPE)) u_volt (
        .clk(clk), .i_total(itot), .v(v_d), .cdt(cdt_d), .vth(vth_d),
        .v_out(v_out), .above(above), .spike(spike));

    iv_dly #(.WD(SW),   .D(VOLT_LAT)) u_itd (clk, itot, i_total);
    iv_dly #(.WD(TAGW), .D(LAT))      u_tag (clk, in_tag, out_tag);

    // valid: the only reset in the pipeline
    reg [LAT-1:0] vld;
    always @(posedge clk) begin
        if (rst) vld <= {LAT{1'b0}};
        else     vld <= {vld[LAT-2:0], in_valid};
    end
    assign out_valid = vld[LAT-1];
endmodule
