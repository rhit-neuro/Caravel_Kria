// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-01 to 2026-11-03.
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// lut_fixed_p6.v -- lut_fixed.v with the last stage split in two: 6 stages.
//
// Why: the timing sweep showed the slowest part of lut_fixed.v is its last
// stage (add b + round + clamp all in one clock). Here it is split:
//
//     stage 1: save the inputs
//     stage 2: add 64 mV, clamp, split, build the address
//     stage 3: read the table (block RAM)
//     stage 4: multiply dy * frac (DSP)
//     stage 5: add b                    (the DSP's built-in adder + register)
//     stage 6: round, clamp to 0..1
//
// See lut_fixed.v for the full explanation of the number formats.
//////////////////////////////////////////////////////////////////////////////////

module lut_fixed_p6 (
    input  wire               clk,
    input  wire               in_valid,
    input  wire signed [26:0] v_in,
    input  wire        [3:0]  curve_sel,
    output reg                out_valid,
    output reg         [17:0] y_out
);

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
    // Stage 2: add 64 mV, clamp, split
    // ---------------------------------------------------------------
    wire signed [27:0] u_sum;
    assign u_sum = v1 + 28'sd33554432;

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

    reg [11:0] addr2;
    reg [17:0] frac2;
    reg        valid2;

    always @(posedge clk) begin
        addr2  <= {sel1, u_clamped[25:18]};
        frac2  <= u_clamped[17:0];
        valid2 <= valid1;
    end

    // ---------------------------------------------------------------
    // Stage 3: read the table
    // ---------------------------------------------------------------
    reg [41:0] word3;
    reg [17:0] frac3;
    reg        valid3;

    always @(posedge clk) begin
        word3  <= table_mem[addr2];
        frac3  <= frac2;
        valid3 <= valid2;
    end

    wire signed [23:0] b3;
    wire signed [17:0] dy3;
    wire signed [18:0] frac3_signed;
    assign b3           = word3[41:18];
    assign dy3          = word3[17:0];
    assign frac3_signed = {1'b0, frac3};

    // ---------------------------------------------------------------
    // Stage 4: multiply
    // ---------------------------------------------------------------
    reg signed [47:0] prod4;
    reg signed [23:0] b4;
    reg               valid4;

    always @(posedge clk) begin
        prod4  <= dy3 * frac3_signed;
        b4     <= b3;
        valid4 <= valid3;
    end

    // ---------------------------------------------------------------
    // Stage 5: add b (moved to 2^-38 units by shifting left 16)
    // ---------------------------------------------------------------
    wire signed [47:0] b4_wide;
    assign b4_wide = b4;

    reg signed [47:0] total5;
    reg               valid5;

    always @(posedge clk) begin
        total5 <= prod4 + (b4_wide <<< 16);
        valid5 <= valid4;
    end

    // ---------------------------------------------------------------
    // Stage 6: round to 18 fraction bits, clamp to 0..1
    // ---------------------------------------------------------------
    wire signed [47:0] rounded;
    assign rounded = total5 + 48'sd524288;

    always @(posedge clk) begin
        out_valid <= valid5;
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
