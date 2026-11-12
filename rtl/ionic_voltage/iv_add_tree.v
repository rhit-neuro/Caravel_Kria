// iv_add_tree.v - registered binary adder tree, one 2-input add per stage.
//
// Stage map: level l (l = 0..LEV-1) adds pairs from level l-1 (level -1 = sign-extended
// inputs, zero-padded to NP = 2^LEV). Latency = LEV = clog2(N). Exact: no rounding, no
// saturation; the caller sizes WO so the sum can't overflow (WO >= WI + clog2(N)).
`timescale 1ns / 1ps
module iv_add_tree #(
    parameter N  = 11,
    parameter WI = 19,
    parameter WO = 22
) (
    input  wire                 clk,
    input  wire [N*WI-1:0]      d,      // N signed words, word k at [k*WI +: WI]
    output wire signed [WO-1:0] sum
);
    localparam LEV = (N <= 1) ? 1 : $clog2(N);
    localparam NP  = 1 << LEV;

    // leaves: sign-extend, pad with zeros
    reg  signed [WO-1:0] leaf [0:NP-1];
    integer k;
    always @(*) begin
        for (k = 0; k < NP; k = k + 1)
            leaf[k] = (k < N) ? {{(WO-WI){d[k*WI+WI-1]}}, d[k*WI +: WI]} : {WO{1'b0}};
    end

    // t[l*NP + i] = node i of level l
    reg signed [WO-1:0] t [0:LEV*NP-1];
    integer l, i;
    always @(posedge clk) begin
        for (i = 0; i < NP/2; i = i + 1)
            t[i] <= leaf[2*i] + leaf[2*i+1];
        for (l = 1; l < LEV; l = l + 1)
            for (i = 0; i < (NP >> (l+1)); i = i + 1)
                t[l*NP + i] <= t[(l-1)*NP + 2*i] + t[(l-1)*NP + 2*i + 1];
    end
    assign sum = t[(LEV-1)*NP];
endmodule
