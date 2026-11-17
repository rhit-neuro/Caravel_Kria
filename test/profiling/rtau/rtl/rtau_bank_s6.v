// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-09.
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// rtau_bank_s6.v -- 9 gate LUTs side by side: 9 parallel 1/tau lookups every clock.
//
// One neuron's 9 gates (mNa has a constant tau, so it is not here) all need 1/tau(V)
// for the SAME membrane voltage V. Each gate gets its own one-curve table
// (rtau_gate_s6.v), so all 9 answers come out together, 6 clocks after V goes in.
// Total table size is the same as one shared 9-curve table, but with 9 read ports
// instead of 1 (block RAM) or 2.
//
// Outputs, W bits each, packed into y_all:  y_all[W*k +: W] = 1/tau of curve k
//     k: 0 hNa, 1 mP, 2 mCaF, 3 hCaF, 4 mCaS, 5 hCaS, 6 mh, 7 mK1, 8 hK1
//////////////////////////////////////////////////////////////////////////////////

module rtau_bank_s6 #(
    parameter W         = 32,
    parameter NB_LOG2   = 8,
    parameter RAM_BLOCK = 0
) (
    input  wire                clk,
    input  wire                in_valid,
    input  wire signed [W-1:0] v_in,
    output wire                out_valid,
    output wire [9*W-1:0]      y_all
);

    wire [8:0] valid_k;            // every gate's valid comes out on the same clock
    assign out_valid = valid_k[0];

    genvar k;
    generate
        for (k = 0; k < 9; k = k + 1) begin : g_gate
            rtau_gate_s6 #(.W(W), .NB_LOG2(NB_LOG2), .RAM_BLOCK(RAM_BLOCK), .CURVE(k)) gate (
                .clk(clk),
                .in_valid(in_valid),
                .v_in(v_in),
                .out_valid(valid_k[k]),
                .y_out(y_all[W*k +: W])
            );
        end
    endgenerate

endmodule
