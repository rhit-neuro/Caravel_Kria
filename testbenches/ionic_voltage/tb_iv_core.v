// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-11.
// tb_iv_core.v - self-checking testbench for iv_core against model/iv_model.py.
//
// Test 1 (stream): NVEC vectors from iv_in_<W>.mem, one per clock with random bubbles.
//   V', {spike, above} and I_total must match iv_exp_<W>.mem bit for bit, in order.
// Test 2 (feedback): NN neurons, STEPS timesteps. Each V' is written back and used as the
//   next step's V (like the real scheduler). Must match iv_fb_exp_<W>.mem.
// Also checks the latency against the stage map (28 for W=18, 36 for W=32).
//
// Vectors: python3 test/ionic_voltage/model/gen_vectors.py (writes the .mem files here).
// Icarus (from testbenches/ionic_voltage):
//   iverilog -g2012 -I../../rtl/ionic_voltage -o tb18.vvp tb_iv_core.v ../../rtl/ionic_voltage/*.v && vvp tb18.vvp
//   add -DIV_W32 (or -Ptb_iv_core.W=32) for the 32-bit build
// Vivado xsim: suites ionic_voltage_18 / ionic_voltage_32 in vivado/config/sources.tcl.
`timescale 1ns / 1ps
`include "iv_defs.vh"
module tb_iv_core;
`ifdef IV_W32
    parameter W     = 32;
`else
    parameter W     = 18;
`endif
    parameter NVEC  = 3000;
    parameter NN    = 8;
    parameter STEPS = 300;

    localparam SW    = W + `IV_SUM_GUARD;
    localparam N_ION = `IV_N_ION, N_M = `IV_N_M, N_H = `IV_N_H;
    localparam NW    = 1 + N_M + N_H + 2 + 3 * N_ION + 2;    // 49 words per record
    localparam ML    = `IV_MPIPE(W) + 3;
    localparam LAT   = 1 + 3 * ML + $clog2(N_ION + 1) + ML + 3;
    localparam TAGW  = 12;

    reg clk = 0, rst = 1;
    always #1.25 clk = ~clk;   // 400 MHz (the period doesn't matter in simulation)

    // ---- vectors ----
    reg [SW-1:0] vin   [0:NVEC*NW-1];
    reg [SW-1:0] vexp  [0:NVEC*3-1];
    reg [SW-1:0] fin   [0:NN*NW-1];
    reg [SW-1:0] fexp  [0:STEPS*NN*2-1];
    reg [8*20-1:0] f_in, f_exp, f_fin, f_fexp;
    initial begin
        f_in   = (W == 18) ? "iv_in_18.mem"     : "iv_in_32.mem";
        f_exp  = (W == 18) ? "iv_exp_18.mem"    : "iv_exp_32.mem";
        f_fin  = (W == 18) ? "iv_fb_in_18.mem"  : "iv_fb_in_32.mem";
        f_fexp = (W == 18) ? "iv_fb_exp_18.mem" : "iv_fb_exp_32.mem";
        $readmemh(f_in,   vin);
        $readmemh(f_exp,  vexp);
        $readmemh(f_fin,  fin);
        $readmemh(f_fexp, fexp);
    end

    // ---- DUT ----
    reg                         in_valid = 0;
    reg  [TAGW-1:0]             in_tag = 0;
    reg  signed [W-1:0]         v_in = 0, i_syn = 0, i_app = 0, cdt = 0, vth = 0;
    reg  [N_M*W-1:0]            m_in = 0;
    reg  [N_H*W-1:0]            h_in = 0;
    reg  [N_ION*W-1:0]          gbar = 0, e_rev = 0;
    reg  [N_ION*`IV_PQ_W-1:0]   pq = 0;
    wire                        out_valid, spike, above;
    wire [TAGW-1:0]             out_tag;
    wire signed [W-1:0]         v_out;
    wire signed [SW-1:0]        i_total;

    iv_core #(.W(W), .TAGW(TAGW)) dut (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_tag(in_tag), .v_in(v_in),
        .m_in(m_in), .h_in(h_in), .i_syn(i_syn), .i_app(i_app), .gbar(gbar), .e_rev(e_rev),
        .pq(pq), .cdt(cdt), .vth(vth), .out_valid(out_valid), .out_tag(out_tag),
        .v_out(v_out), .spike(spike), .above(above), .i_total(i_total));

    // load record r from memory "which" (0 = stream, 1 = feedback) onto the DUT inputs
    task load(input integer which, input integer r);
        integer k, b;
        reg [SW-1:0] wd;
        begin
            for (k = 0; k < NW; k = k + 1) begin
                b  = r * NW + k;
                wd = which ? fin[b] : vin[b];
                if (k == 0)                    v_in = wd[W-1:0];
                else if (k < 1 + N_M)          m_in[(k-1)*W +: W] = wd[W-1:0];
                else if (k < 1 + N_M + N_H)    h_in[(k-1-N_M)*W +: W] = wd[W-1:0];
                else if (k == 1 + N_M + N_H)   i_syn = wd[W-1:0];
                else if (k == 2 + N_M + N_H)   i_app = wd[W-1:0];
                else if (k < 3 + N_M + N_H + N_ION)   gbar[(k-3-N_M-N_H)*W +: W] = wd[W-1:0];
                else if (k < 3 + N_M + N_H + 2*N_ION) e_rev[(k-3-N_M-N_H-N_ION)*W +: W] = wd[W-1:0];
                else if (k < 3 + N_M + N_H + 3*N_ION) pq[(k-3-N_M-N_H-2*N_ION)*`IV_PQ_W +: `IV_PQ_W] = wd[`IV_PQ_W-1:0];
                else if (k == 3 + N_M + N_H + 3*N_ION) cdt = wd[W-1:0];
                else                                   vth = wd[W-1:0];
            end
        end
    endtask

    integer errors = 0, n_out = 0, n_spk = 0, seed = 7;
    integer t_first_in = -1, t_first_out = -1, cyc = 0;
    integer mode = 0;           // 0 = stream test, 1 = feedback
    integer step = 0, fb_got = 0;
    reg signed [W-1:0] vstate [0:NN-1];

    always @(posedge clk) cyc <= cyc + 1;

    // ---- checker ----
    always @(posedge clk) if (out_valid) begin
        if (t_first_out < 0) t_first_out = cyc;
        if (mode == 0) begin
            if (out_tag !== n_out[TAGW-1:0] ||
                v_out   !== vexp[n_out*3][W-1:0] ||
                {spike, above} !== vexp[n_out*3+1][1:0] ||
                i_total !== vexp[n_out*3+2]) begin
                if (errors < 10)
                    $display("STREAM MISMATCH vec %0d tag %0d: V' %h exp %h | sa %b%b exp %b | Itot %h exp %h",
                             n_out, out_tag, v_out, vexp[n_out*3][W-1:0], spike, above,
                             vexp[n_out*3+1][1:0], i_total, vexp[n_out*3+2]);
                errors = errors + 1;
            end
            n_spk = n_spk + spike;
            n_out = n_out + 1;
        end else begin
            if (v_out !== fexp[(step*NN + out_tag)*2][W-1:0] ||
                {spike, above} !== fexp[(step*NN + out_tag)*2+1][1:0]) begin
                if (errors < 10)
                    $display("FEEDBACK MISMATCH step %0d neuron %0d: V' %h exp %h", step, out_tag,
                             v_out, fexp[(step*NN + out_tag)*2][W-1:0]);
                errors = errors + 1;
            end
            vstate[out_tag] = v_out;
            fb_got = fb_got + 1;
        end
    end

    integer r, n;
    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk) rst = 0;

        // ---- test 1: stream with random bubbles ----
        r = 0;
        while (r < NVEC) begin
            @(negedge clk);
            if (($random(seed) & 3) != 0) begin
                load(0, r);
                in_valid = 1; in_tag = r[TAGW-1:0];
                if (t_first_in < 0) t_first_in = cyc;
                r = r + 1;
            end else
                in_valid = 0;
        end
        @(negedge clk) in_valid = 0;
        wait (n_out == NVEC);
        $display("W=%0d stream : %0d vectors, %0d errors, %0d spikes, latency %0d (expected %0d)",
                 W, NVEC, errors, n_spk, t_first_out - t_first_in, LAT);
        if (t_first_out - t_first_in != LAT) errors = errors + 1;

        // ---- test 2: feedback (V' -> next V), NN neurons back to back each step ----
        repeat (5) @(posedge clk);
        mode = 1;
        for (n = 0; n < NN; n = n + 1) vstate[n] = fin[n*NW][W-1:0];
        for (step = 0; step < STEPS; step = step + 1) begin
            fb_got = 0;
            for (n = 0; n < NN; n = n + 1) begin
                @(negedge clk);
                load(1, n);
                v_in = vstate[n];
                in_valid = 1; in_tag = n;
            end
            @(negedge clk) in_valid = 0;
            wait (fb_got == NN);
            @(negedge clk);
        end
        $display("W=%0d feedback: %0d neurons x %0d steps, total errors %0d", W, NN, STEPS, errors);
        if (errors == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
