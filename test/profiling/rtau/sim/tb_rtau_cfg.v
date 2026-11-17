// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-09.
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_rtau_cfg.v -- testbench for the 1/tau LUT (rtau_lut_s4 / s6 / s7), any configuration.
//
// run_sim.bat writes cfg.vh, which says which module and which configuration to test:
//     `define LUT_TOP rtau_lut_s6     `define W 32     `define NSAMP 256     `define RAM_BLOCK 1
//     `include "tb_w32_n256.vh"       (N_TESTS, TV_IN, TV_OUT, made by model/gen_rtau_cfg.py)
//
// Sends one test input per clock, checks every answer bit for bit against the
// Python bit-exact model, and measures the latency (clocks from input to answer).
//////////////////////////////////////////////////////////////////////////////////
`include "cfg.vh"

module tb_rtau_cfg;

    localparam W       = `W;
    localparam NB_LOG2 = (`NSAMP == 128) ? 7 : 8;

    reg clk = 0;
    always #5 clk = ~clk;          // 10 ns clock (speed does not matter in this test)

    reg                in_valid  = 0;
    reg signed [W-1:0] v_in      = 0;
    reg        [3:0]   curve_sel = 0;
    wire               out_valid;
    wire       [W-1:0] y_out;

    // RTL: the module takes the configuration as parameters.
    // Gate level (`define NETLIST): Vivado's netlist has the configuration built in, so no parameters.
`ifdef NETLIST
    `LUT_TOP dut (
`else
    `LUT_TOP #(.W(W), .NB_LOG2(NB_LOG2), .RAM_BLOCK(`RAM_BLOCK)) dut (
`endif
        .clk(clk),
        .in_valid(in_valid),
        .v_in(v_in),
        .curve_sel(curve_sel),
        .out_valid(out_valid),
        .y_out(y_out)
    );

    reg [W+3:0] tv_in  [0:`N_TESTS-1];       // {curve_sel, v}
    reg [W-1:0] tv_out [0:`N_TESTS-1];       // expected y

    integer sent      = 0;
    integer checked   = 0;
    integer errors    = 0;
    integer cycle     = 0;
    integer first_in  = -1;
    integer first_out = -1;

    initial begin
        $readmemh(`TV_IN, tv_in);
        $readmemh(`TV_OUT, tv_out);
    end

    always @(posedge clk) cycle <= cycle + 1;

    // Send one test per clock, after 20 clocks (gate-level sims hold everything in reset for 100 ns)
    always @(posedge clk) begin
        if (cycle >= 20 && sent < `N_TESTS) begin
            in_valid  <= 1;
            curve_sel <= tv_in[sent][W+3:W];
            v_in      <= tv_in[sent][W-1:0];
            sent      <= sent + 1;
        end
        else begin
            in_valid <= 0;
        end
    end

    // Latency, edge to edge: first edge where the DUT sees in_valid -> first edge where we see out_valid
    always @(posedge clk) begin
        if (in_valid && first_in < 0) first_in <= cycle;
    end

    always @(posedge clk) begin
        if (out_valid) begin
            if (first_out < 0) first_out <= cycle;
            if (y_out !== tv_out[checked]) begin
                errors <= errors + 1;
                if (errors < 10)
                    $display("MISMATCH test %0d: sel=%0d v=%h  got %h  expected %h",
                             checked, tv_in[checked][W+3:W], tv_in[checked][W-1:0], y_out, tv_out[checked]);
            end
            checked <= checked + 1;
        end
    end

    always @(posedge clk) begin
        if (checked == `N_TESTS) begin
            $display("RESULT: W=%0d samples=%0d ram_block=%0d: %0d tests, %0d errors, latency %0d clocks",
                     W, `NSAMP, `RAM_BLOCK, checked, errors, first_out - first_in);
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
