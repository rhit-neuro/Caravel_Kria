// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-09.
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// rtau_lut_s4.v -- 1/tau lookup table, 4 pipeline stages. No comparisons, no divide.
//
// The table holds 1/tau (1/s) for 9 gate curves, as a straight line per piece:
//     u     = v + 64mV;                  // make the input non-negative
//     index = top K bits of u;           // which piece (K = 7 -> 128 pieces, 8 -> 256)
//     frac  = the rest of u;             // where inside the piece
//     b, dy = table[curve_sel][index];   // line value at the piece start, change across the piece
//     y     = b + dy * frac / 2^FW;      // straight line inside the piece
//
// ONE number format for everything (v_in, b, dy, y_out), signed fixed point:
//     W = 18 : Q10.7   (1 sign + 10 integer + 7 fraction bits)
//     W = 32 : Q10.21  (1 sign + 10 integer + 21 fraction bits)
// v_in is in mV, y_out is 1/tau in 1/s (always >= 0).
//
// Parameters (set by whoever uses this module):
//     W         18 or 32           number size
//     NB_LOG2   7 or 8             128 or 256 pieces (samples) per curve
//     RAM_BLOCK 1 or 0             1 = table in block RAM, 0 = table in distributed RAM (LUTs)
//
// Bit slicing (F = fraction bits, FW = F + 7 - NB_LOG2):
//     u     : F+7 bits   (V + 64 mV, clamped to 0 .. 128 mV)
//     index = u[F+6 : FW]           frac = u[FW-1 : 0]
//     addr  = {curve_sel, index}
//     e.g. W=32, 256 pieces: index = u[27:20], frac = u[19:0]
//
// Timing: one new input every clock. The answer comes out 4 clocks later.
//     stage 1: add 64 mV, clamp, split, build the address
//     stage 2: read the table
//     stage 3: multiply dy * frac (DSP; two DSPs chained when W = 32)
//     stage 4: add b, round, clamp to 0 .. largest positive number
//
// curve_sel: 0 hNa, 1 mP, 2 mCaF, 3 hCaF, 4 mCaS, 5 hCaS, 6 mh, 7 mK1, 8 hK1 (9-15 unused).
// mNa has a constant tau (1/tau = 10000 1/s), so it is not in the table.
// Table files rtau_w<W>_n<pieces>.mem are made by model/gen_rtau_cfg.py.
//////////////////////////////////////////////////////////////////////////////////

module rtau_lut_s4 #(
    parameter W         = 32,
    parameter NB_LOG2   = 8,
    parameter RAM_BLOCK = 1
) (
    input  wire                clk,
    input  wire                in_valid,    // 1 = v_in and curve_sel hold a new input
    input  wire signed [W-1:0] v_in,        // membrane voltage, mV
    input  wire        [3:0]   curve_sel,   // which curve (see list above)
    output reg                 out_valid,   // 1 = y_out holds an answer
    output reg         [W-1:0] y_out        // 1/tau, 1/s
);

    // ---------------------------------------------------------------
    // Sizes worked out from the parameters (like #define in C)
    // ---------------------------------------------------------------
    localparam F     = (W == 18) ? 7 : 21;           // fraction bits
    localparam UW    = F + 7;                        // bits of u (covers 128 mV)
    localparam FW    = UW - NB_LOG2;                 // bits of frac
    localparam AW    = 4 + NB_LOG2;                  // address bits
    localparam DEPTH = 16 << NB_LOG2;                // table words
    localparam integer OFFSET = 1 << (F + 6);        // 64 mV in our units
    localparam integer MAXU   = (1 << UW) - 1;       // +64 mV (end of the table)
    localparam integer YMAX   = (1 << (W - 1)) - 1;  // largest positive number
    localparam TW    = W + FW + 2;                   // bits of the sum (no overflow)
    localparam MEMFILE = (W == 18) ? ((NB_LOG2 == 7) ? "rtau_w18_n128.mem" : "rtau_w18_n256.mem")
                                   : ((NB_LOG2 == 7) ? "rtau_w32_n128.mem" : "rtau_w32_n256.mem");

    // (no input register in this version: the inputs go straight into stage 1)
    wire signed [W-1:0] v1;
    wire        [3:0]   sel1;
    wire                valid1;
    assign v1     = v_in;
    assign sel1   = curve_sel;
    assign valid1 = in_valid;

    // ---------------------------------------------------------------
    // Stage 1: add 64 mV, clamp, split into index and frac
    // ---------------------------------------------------------------
    wire signed [W:0] u_sum;                 // one extra bit so the add cannot overflow
    assign u_sum = v1 + OFFSET;

    reg [UW-1:0] u_clamped;

    always @(*) begin
        if (u_sum < 0) begin
            u_clamped = 0;                   // below -64 mV: start of the first piece
        end
        else if (u_sum > MAXU) begin
            u_clamped = MAXU;                // above +64 mV: end of the last piece
        end
        else begin
            u_clamped = u_sum[UW-1:0];
        end
    end

    reg [AW-1:0] addr2;
    reg [FW-1:0] frac2;
    reg          valid2;

    always @(posedge clk) begin
        addr2  <= {sel1, u_clamped[UW-1:FW]};    // top bits of u = piece number
        frac2  <= u_clamped[FW-1:0];             // low bits of u = place inside the piece
        valid2 <= valid1;
    end

    // ---------------------------------------------------------------
    // Stage 2: read the table. Each word is {b (W bits), dy (W bits)}.
    // The two copies below are the same table; RAM_BLOCK picks which
    // kind of memory Vivado builds it from.
    // ---------------------------------------------------------------
    reg [2*W-1:0] word3;
    reg [FW-1:0]  frac3;
    reg           valid3;

    generate
        if (RAM_BLOCK == 1) begin : g_bram
            (* rom_style = "block", ram_style = "block" *)
            reg [2*W-1:0] table_mem [0:DEPTH-1];
            initial $readmemh(MEMFILE, table_mem);
            always @(posedge clk) word3 <= table_mem[addr2];
        end
        else begin : g_dist
            (* rom_style = "distributed", ram_style = "distributed" *)
            reg [2*W-1:0] table_mem [0:DEPTH-1];
            initial $readmemh(MEMFILE, table_mem);
            always @(posedge clk) word3 <= table_mem[addr2];
        end
    endgenerate

    always @(posedge clk) begin
        frac3  <= frac2;
        valid3 <= valid2;
    end

    wire signed [W-1:0] b3;
    wire signed [W-1:0] dy3;
    assign b3  = word3[2*W-1:W];
    assign dy3 = word3[W-1:0];

    // ---------------------------------------------------------------
    // Stage 3: multiply dy * frac. frac is unsigned, so put a 0 on top
    // to make it a positive signed number (Verilog multiplies signed
    // only if BOTH sides are signed).
    // ---------------------------------------------------------------
    wire signed [FW:0] frac3_signed;
    assign frac3_signed = {1'b0, frac3};

    reg signed [W+FW:0] prod4;
    reg signed [W-1:0]  b4;
    reg                 valid4;

    always @(posedge clk) begin
        prod4  <= dy3 * frac3_signed;
        b4     <= b3;
        valid4 <= valid3;
    end

    // ---------------------------------------------------------------
    // Stage 4: add b, round, clamp (one clock). b has F fraction bits,
    // the product has F + FW, so shift b left by FW first. Rounding:
    // add half of the step we drop, then drop FW bits.
    // ---------------------------------------------------------------
    wire signed [TW-1:0] b4_wide;
    wire signed [TW-1:0] total4;
    wire signed [TW-1:0] rounded;
    wire signed [TW-1:0] y_full;
    assign b4_wide = b4;                       // sign-extend
    assign total4  = prod4 + (b4_wide <<< FW);
    assign rounded = total4 + (1 <<< (FW - 1));
    assign y_full  = rounded >>> FW;

    always @(posedge clk) begin
        out_valid <= valid4;
        if (y_full < 0) begin
            y_out <= 0;
        end
        else if (y_full > YMAX) begin
            y_out <= YMAX;
        end
        else begin
            y_out <= y_full[W-1:0];
        end
    end

endmodule
