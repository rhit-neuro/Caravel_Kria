// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-01 to 2026-11-03.
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_lut_fixed.v -- testbench for lut_fixed.v
//
// Reads test inputs and the expected answers made by model/gen_fixed_lut.py,
// sends one input per clock, and checks every answer bit for bit.
// Also measures the latency (clocks from input to answer).
//
// Files (in the simulation folder):
//   tv_in.mem     one line per test: {curve_sel (4 bits), v (27 bits)}
//   tv_out.mem    one line per test: expected y (18 bits)
//   tb_params.vh  defines N_TESTS
//////////////////////////////////////////////////////////////////////////////////
`include "tb_params.vh"

module tb_lut_fixed;

    reg clk = 0;
    always #5 clk = ~clk;          // 10 ns clock (speed does not matter in this test)

    // DUT signals
    reg               in_valid  = 0;
    reg signed [26:0] v_in      = 0;
    reg        [3:0]  curve_sel = 0;
    wire              out_valid;
    wire       [17:0] y_out;

    // Which version to test: run_sim.bat writes lut_top.vh with one line,
    // e.g.  `define LUT_TOP lut_fixed_p3      (default: lut_fixed, the 5-stage one)
`include "lut_top.vh"
`ifndef LUT_TOP
`define LUT_TOP lut_fixed
`endif

    `LUT_TOP dut (
        .clk(clk),
        .in_valid(in_valid),
        .v_in(v_in),
        .curve_sel(curve_sel),
        .out_valid(out_valid),
        .y_out(y_out)
    );

    // Test data
    reg [30:0] tv_in  [0:`N_TESTS-1];
    reg [17:0] tv_out [0:`N_TESTS-1];

    integer sent      = 0;     // inputs sent so far
    integer checked   = 0;     // answers checked so far
    integer errors    = 0;
    integer cycle     = 0;
    integer first_in  = -1;
    integer first_out = -1;

    initial begin
        $readmemh("tv_in.mem", tv_in);
        $readmemh("tv_out.mem", tv_out);
    end

    // Count clocks
    always @(posedge clk) begin
        cycle <= cycle + 1;
    end

    // Send one test per clock.
    // Wait 20 clocks first: in gate-level simulation the whole chip is held in
    // reset for the first 100 ns (global reset, GSR), and inputs sent then are lost.
    always @(posedge clk) begin
        if (cycle >= 20 && sent < `N_TESTS) begin
            in_valid  <= 1;
            curve_sel <= tv_in[sent][30:27];
            v_in      <= tv_in[sent][26:0];
            sent      <= sent + 1;
        end
        else begin
            in_valid <= 0;
        end
    end

    // Latency is measured edge to edge: the first clock edge where the DUT
    // SEES in_valid = 1, to the first edge where we SEE out_valid = 1.
    always @(posedge clk) begin
        if (in_valid && first_in < 0) first_in <= cycle;
    end

    // Check each answer, in the same order the inputs went in
    always @(posedge clk) begin
        if (out_valid) begin
            if (first_out < 0) first_out <= cycle;
            if (y_out !== tv_out[checked]) begin
                errors <= errors + 1;
                if (errors < 10) begin
                    $display("MISMATCH test %0d: sel=%0d v=%h  got %h  expected %h",
                             checked, tv_in[checked][30:27], tv_in[checked][26:0], y_out, tv_out[checked]);
                end
            end
            checked <= checked + 1;
        end
    end

    // Finish when every answer has been checked (or after a timeout)
    always @(posedge clk) begin
        if (checked == `N_TESTS) begin
            $display("RESULT: %0d tests, %0d errors, latency %0d clocks", checked, errors, first_out - first_in);
            if (errors == 0) $display("PASS");
            else             $display("FAIL");
            $finish;
        end
        if (cycle > `N_TESTS + 100) begin
            $display("TIMEOUT: only %0d of %0d answers came out", checked, `N_TESTS);
            $finish;
        end
    end

endmodule
