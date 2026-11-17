// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-01 to 2026-11-03.
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// lut_fixed.v
//
// Bit-indexed lookup table for the gate curves (f_inf). No comparisons.
//
// What it does (same as this C code):
//
//     u     = v + 64mV;                  // make the input non-negative
//     index = u >> 18;                   // which 0.5 mV bin (top 8 bits)
//     frac  = u & 0x3FFFF;               // where inside the bin (low 18 bits)
//     b     = table_b [curve_sel][index];
//     dy    = table_dy[curve_sel][index];
//     y     = b + dy * frac / 2^18;      // straight line inside the bin
//
// Number formats (all plain integers in hardware):
//     v_in   27-bit signed, mV with 19 fraction bits (1 = 2^-19 mV)
//     y_out  18-bit unsigned, 18 fraction bits (gate value 0 .. 0.999996)
//     b      24-bit signed, 22 fraction bits
//     dy     18-bit signed, 20 fraction bits
//
// Timing: one new input every clock. The answer comes out 5 clocks later.
//     stage 1: save the inputs in registers
//     stage 2: add 64 mV, split into index + frac, build the table address
//     stage 3: read the table (block RAM)
//     stage 4: multiply dy * frac (DSP)
//     stage 5: add b, round, clamp to 0..1
//
// The table file lut_fixed.mem is made by model/gen_fixed_lut.py.
//////////////////////////////////////////////////////////////////////////////////

module lut_fixed (
    input  wire               clk,
    input  wire               in_valid,    // 1 = v_in and curve_sel hold a new input
    input  wire signed [26:0] v_in,        // membrane voltage
    input  wire        [3:0]  curve_sel,   // 0 hNa, 1 mNa, 2 mP, 3 mCaF, 4 hCaF, 5 mCaS, 6 hCaS, 7 mh, 8 mK1, 9 hK1
    output reg                out_valid,   // 1 = y_out holds an answer
    output reg         [17:0] y_out        // gate value
);

    // ---------------------------------------------------------------
    // The table: 16 curves x 256 bins = 4096 words.
    // Each word is 42 bits: {b (24 bits), dy (18 bits)}.
    // Like a C array:  uint64_t table[4096];  filled from a file.
    // ---------------------------------------------------------------
    reg [41:0] table_mem [0:4095];

    initial begin
        $readmemh("lut_fixed.mem", table_mem);
    end

    // ---------------------------------------------------------------
    // Stage 1: save the inputs
    // ---------------------------------------------------------------
    reg signed [26:0] v1;
    reg        [3:0]  sel1;
    reg               valid1;

    always @(posedge clk) begin
        v1     <= v_in;
        sel1   <= curve_sel;
        valid1 <= in_valid;
    end

    // ---------------------------------------------------------------
    // Stage 2: add 64 mV, clamp, split into index and frac
    // ---------------------------------------------------------------
    // 64 mV in our units is 64 * 2^19 = 2^25 = 33554432.
    // u is 28 bits so the sum cannot overflow.
    wire signed [27:0] u_sum;
    assign u_sum = v1 + 28'sd33554432;

    reg [25:0] u_clamped;        // 0 .. 2^26-1, covers -64 mV .. +64 mV

    always @(*) begin
        if (u_sum < 0) begin
            u_clamped = 26'd0;                   // below -64 mV: use the first bin
        end
        else if (u_sum > 28'sd67108863) begin
            u_clamped = 26'h3FFFFFF;             // at or above +64 mV: use the end of the last bin
        end
        else begin
            u_clamped = u_sum[25:0];
        end
    end

    reg [11:0] addr2;           // {curve_sel, index}
    reg [17:0] frac2;
    reg        valid2;

    always @(posedge clk) begin
        addr2  <= {sel1, u_clamped[25:18]};      // top 8 bits of u = bin number
        frac2  <= u_clamped[17:0];               // low 18 bits of u = place inside the bin
        valid2 <= valid1;
    end

    // ---------------------------------------------------------------
    // Stage 3: read the table
    // (reading on the clock edge lets Vivado put the table in block RAM)
    // ---------------------------------------------------------------
    reg [41:0] word3;
    reg [17:0] frac3;
    reg        valid3;

    always @(posedge clk) begin
        word3  <= table_mem[addr2];
        frac3  <= frac2;
        valid3 <= valid2;
    end

    // Split the word into its two numbers.
    wire signed [23:0] b3;
    wire signed [17:0] dy3;
    assign b3  = word3[41:18];
    assign dy3 = word3[17:0];

    // ---------------------------------------------------------------
    // Stage 4: multiply  dy * frac
    // frac is unsigned, dy is signed. Verilog only does a signed multiply
    // if BOTH sides are signed, so put a 0 on top of frac to make it a
    // positive 19-bit signed number.
    // ---------------------------------------------------------------
    wire signed [18:0] frac3_signed;
    assign frac3_signed = {1'b0, frac3};

    reg signed [47:0] prod4;     // units of 2^-38 (20 + 18 fraction bits)
    reg signed [23:0] b4;
    reg               valid4;

    always @(posedge clk) begin
        prod4  <= dy3 * frac3_signed;
        b4     <= b3;
        valid4 <= valid3;
    end

    // ---------------------------------------------------------------
    // Stage 5: add b, round to 18 fraction bits, clamp to 0..1
    // ---------------------------------------------------------------
    // b has 22 fraction bits; the product has 38. Shift b left by 16
    // so both are in units of 2^-38, then add.
    wire signed [47:0] b4_wide;
    wire signed [47:0] total;
    wire signed [47:0] rounded;
    assign b4_wide = b4;                         // sign-extend to 48 bits
    assign total   = prod4 + (b4_wide <<< 16);

    // Rounding: add half of the step we are about to drop (2^19), then drop 20 bits.
    // Dropping bits = taking bits [47:20], like (total + 2^19) >> 20 in C.
    assign rounded = total + 48'sd524288;

    always @(posedge clk) begin
        out_valid <= valid4;
        if (rounded[47] == 1'b1) begin
            y_out <= 18'd0;                      // negative -> 0
        end
        else if (rounded[47:20] > 28'd262143) begin
            y_out <= 18'h3FFFF;                  // above 1 -> largest value
        end
        else begin
            y_out <= rounded[37:20];
        end
    end

endmodule
