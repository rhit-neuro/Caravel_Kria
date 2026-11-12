// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-11.
// iv_dly.v - D-cycle delay line (D = 0 is a wire). No reset, so Vivado maps long ones to SRLs.
`timescale 1ns / 1ps
module iv_dly #(
    parameter WD = 1,
    parameter D  = 1
) (
    input  wire          clk,
    input  wire [WD-1:0] d,
    output wire [WD-1:0] q
);
    generate
        if (D == 0) begin : g_wire
            assign q = d;
        end else begin : g_reg
            reg [WD-1:0] sr [0:D-1];
            integer i;
            always @(posedge clk) begin
                sr[0] <= d;
                for (i = 1; i < D; i = i + 1)
                    sr[i] <= sr[i-1];
            end
            assign q = sr[D-1];
        end
    endgenerate
endmodule
