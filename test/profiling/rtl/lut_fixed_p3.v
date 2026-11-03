// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-01 to 2026-11-03.
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// lut_fixed_p3.v -- SHORT version of lut_fixed.v: same math, 3 stages instead of 5.
//
//     stage 1: add 64 mV, clamp, split into index + frac, build the address
//              (done straight from the input pins -- no separate input register)
//     stage 2: read the table (block RAM)
//     stage 3: multiply dy * frac, add b, round, clamp -- all in one clock
//
// Fewer stages = fewer clocks of delay, but more work squeezed into each clock,
// so it cannot run as fast. The timing sweep measures how fast.
// See lut_fixed.v for the full explanation of the number formats.
//////////////////////////////////////////////////////////////////////////////////

module lut_fixed_p3 (
    input  wire               clk,
    input  wire               in_valid,
    input  wire signed [26:0] v_in,        // mV, 19 fraction bits
    input  wire        [3:0]  curve_sel,
    output reg                out_valid,
    output reg         [17:0] y_out        // gate value, 18 fraction bits
);

    reg [41:0] table_mem [0:4095];         // {b (24 bits), dy (18 bits)}

    initial begin
        $readmemh("lut_fixed.mem", table_mem);
    end

    // ---------------------------------------------------------------
    // Stage 1: add 64 mV (= 2^25), clamp, split
    // ---------------------------------------------------------------
    wire signed [27:0] u_sum;
    assign u_sum = v_in + 28'sd33554432;

    reg [25:0] u_clamped;

    always @(*) begin
        if (u_sum < 0) begin
            u_clamped = 26'd0;
        end
        else if (u_sum > 28'sd67108863) begin
            u_clamped = 26'h3FFFFFF;
        end
        else begin
            u_clamped = u_sum[25:0];
        end
    end

    reg [11:0] addr1;
    reg [17:0] frac1;
    reg        valid1;

    always @(posedge clk) begin
        addr1  <= {curve_sel, u_clamped[25:18]};
        frac1  <= u_clamped[17:0];
        valid1 <= in_valid;
    end

    // ---------------------------------------------------------------
    // Stage 2: read the table
    // ---------------------------------------------------------------
    reg [41:0] word2;
    reg [17:0] frac2;
    reg        valid2;

    always @(posedge clk) begin
        word2  <= table_mem[addr1];
        frac2  <= frac1;
        valid2 <= valid1;
    end

    // ---------------------------------------------------------------
    // Stage 3: multiply, add, round, clamp (one clock)
    // ---------------------------------------------------------------
    wire signed [23:0] b2;
    wire signed [17:0] dy2;
    wire signed [18:0] frac2_signed;
    assign b2           = word2[41:18];
    assign dy2          = word2[17:0];
    assign frac2_signed = {1'b0, frac2};

    wire signed [47:0] prod;
    wire signed [47:0] b2_wide;
    wire signed [47:0] total;
    wire signed [47:0] rounded;
    assign prod    = dy2 * frac2_signed;
    assign b2_wide = b2;
    assign total   = prod + (b2_wide <<< 16);
    assign rounded = total + 48'sd524288;

    always @(posedge clk) begin
        out_valid <= valid2;
        if (rounded[47] == 1'b1) begin
            y_out <= 18'd0;
        end
        else if (rounded[47:20] > 28'd262143) begin
            y_out <= 18'h3FFFF;
        end
        else begin
            y_out <= rounded[37:20];
        end
    end

endmodule
