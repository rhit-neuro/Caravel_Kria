// iv_voltage.v - Voltage Module: forward-Euler membrane update and threshold compare.
//
//   dV    = cdt * I_total                 cdt = dt / C_m (V per nA), rounded + saturated to W+1
//   V'    = sat_W(V - dV)
//   above = V' >= Vth
//   spike = above & ~(V >= Vth)           rising crossing, one pulse per spike
//
// Stage map (LAT = ML + 3, ML = MPIPE + 3):
//   s0 .. ML-1 : dV = iv_mul(I_total, cdt);  V, Vth delayed;  was = (V >= Vth) at s0
//   ML         : dif = V - dV               (W+2 bits)
//   ML+1       : vn  = saturate(dif)        (W bits)
//   ML+2       : v_out = vn; above = vn >= Vth; spike = above & ~was
// v, cdt, vth must arrive on the same cycle as i_total.
`timescale 1ns / 1ps
`include "iv_defs.vh"
module iv_voltage #(
    parameter W     = 18,
    parameter MPIPE = `IV_MPIPE(W)
) (
    input  wire                                clk,
    input  wire signed [W+`IV_SUM_GUARD-1:0]   i_total,
    input  wire signed [W-1:0]                 v,
    input  wire signed [W-1:0]                 cdt,     // must be >= 0
    input  wire signed [W-1:0]                 vth,
    output reg  signed [W-1:0]                 v_out,
    output reg                                 above,
    output reg                                 spike
);
    localparam VF = `IV_VF(W);
    localparam IF = `IV_IF(W);
    localparam CF = `IV_CF(W);
    localparam SW = W + `IV_SUM_GUARD;
    localparam ML = MPIPE + 3;

    wire signed [W:0] dv;
    iv_mul #(.AW(SW), .BW(W), .SHIFT(IF+CF-VF), .OW(W+1), .MPIPE(MPIPE)) u_dv (clk, i_total, cdt, dv);

    reg was_r;
    always @(posedge clk) was_r <= (v >= vth);

    wire signed [W-1:0] v_d, vth_d;
    wire                was_d;
    iv_dly #(.WD(2*W), .D(ML))   u_v   (clk, {v, vth}, {v_d, vth_d});
    iv_dly #(.WD(1),   .D(ML-1)) u_was (clk, was_r, was_d);

    // ML: subtract
    reg signed [W+1:0] dif_r;
    reg signed [W-1:0] vth_1;
    reg                was_1;
    always @(posedge clk) begin
        dif_r <= {{2{v_d[W-1]}}, v_d} - {dv[W], dv};
        vth_1 <= vth_d;
        was_1 <= was_d;
    end

    // ML+1: saturate to W bits
    reg signed [W-1:0] vn_r, vth_2;
    reg                was_2;
    wire fits = (dif_r[W+1:W-1] == 3'b000) | (dif_r[W+1:W-1] == 3'b111);
    always @(posedge clk) begin
        if (fits)             vn_r <= dif_r[W-1:0];
        else if (dif_r[W+1])  vn_r <= {1'b1, {(W-1){1'b0}}};
        else                  vn_r <= {1'b0, {(W-1){1'b1}}};
        vth_2 <= vth_1;
        was_2 <= was_1;
    end

    // ML+2: compare
    always @(posedge clk) begin
        v_out <= vn_r;
        above <= (vn_r >= vth_2);
        spike <= (vn_r >= vth_2) & ~was_2;
    end
endmodule
