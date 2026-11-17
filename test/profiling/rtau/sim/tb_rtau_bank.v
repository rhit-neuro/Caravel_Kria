// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-09.
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_rtau_bank.v -- testbench for rtau_bank_s6 (9 gates, 9 parallel lookups per clock).
// run_bank_sim.bat writes cfgb.vh:  `define W ..  `define NSAMP ..  `define RAM_BLOCK ..
//                                   `include "tbb_w<W>_n<N>.vh"  (+ `define NETLIST for gate level)
// Sends one V per clock; checks all 9 answers of every V bit for bit.
//////////////////////////////////////////////////////////////////////////////////
`include "cfgb.vh"

module tb_rtau_bank;

    localparam W       = `W;
    localparam NB_LOG2 = (`NSAMP == 128) ? 7 : 8;

    reg clk = 0;
    always #5 clk = ~clk;

    reg                in_valid = 0;
    reg signed [W-1:0] v_in     = 0;
    wire               out_valid;
    wire [9*W-1:0]     y_all;

`ifdef NETLIST
    rtau_bank_top dut (
`else
    rtau_bank_s6 #(.W(W), .NB_LOG2(NB_LOG2), .RAM_BLOCK(`RAM_BLOCK)) dut (
`endif
        .clk(clk), .in_valid(in_valid), .v_in(v_in), .out_valid(out_valid), .y_all(y_all));

    reg [W-1:0] tv_in  [0:`N_TESTS-1];
    reg [W-1:0] tv_out [0:9*`N_TESTS-1];      // 9 answers per input

    integer sent = 0, checked = 0, errors = 0, cycle = 0, first_in = -1, first_out = -1, k;

    initial begin
        $readmemh(`TV_IN, tv_in);
        $readmemh(`TV_OUT, tv_out);
    end

    always @(posedge clk) cycle <= cycle + 1;

    always @(posedge clk) begin
        if (cycle >= 20 && sent < `N_TESTS) begin
            in_valid <= 1;
            v_in     <= tv_in[sent];
            sent     <= sent + 1;
        end
        else begin
            in_valid <= 0;
        end
    end

    always @(posedge clk) begin
        if (in_valid && first_in < 0) first_in <= cycle;
    end

    always @(posedge clk) begin
        if (out_valid) begin
            if (first_out < 0) first_out <= cycle;
            for (k = 0; k < 9; k = k + 1) begin
                if (y_all[W*k +: W] !== tv_out[9*checked + k]) begin
                    errors = errors + 1;
                    if (errors < 10)
                        $display("MISMATCH input %0d gate %0d: v=%h got %h expected %h",
                                 checked, k, tv_in[checked], y_all[W*k +: W], tv_out[9*checked + k]);
                end
            end
            checked <= checked + 1;
        end
    end

    always @(posedge clk) begin
        if (checked == `N_TESTS) begin
            $display("RESULT: bank W=%0d samples=%0d ram_block=%0d: %0d inputs x 9 gates, %0d errors, latency %0d clocks",
                     W, `NSAMP, `RAM_BLOCK, checked, errors, first_out - first_in);
            if (errors == 0) $display("PASS"); else $display("FAIL");
            $finish;
        end
        if (cycle > `N_TESTS + 100) begin
            $display("TIMEOUT: only %0d of %0d answers came out", checked, `N_TESTS);
            $finish;
        end
    end
endmodule
