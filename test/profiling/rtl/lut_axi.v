// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-01 to 2026-11-03.
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// lut_axi.v -- register block so Linux on the KR260 can use the LUT.
//
// Linux sees this block as 16 x 32-bit registers starting at 0xA000_0000.
// (Like a C struct at a fixed address:  volatile uint32_t *regs = mmap(...);)
//
//   offset name          R/W  meaning
//   0x00   ID            R    always 0x4C555442 ("LUTB"); check this first
//   0x04   INFO          R    [7:0] LUT stages (3..7), [19:8] clock in MHz the bitstream was built for
//   0x08   V_IN          R/W  [26:0] voltage, Q7.19 mV (same format as lut_fixed.v)
//   0x0C   CURVE_SEL     R/W  [3:0] 0 hNa, 1 mNa, ... 9 hK1
//   0x10   CTRL          W    write 1 = one lookup of V_IN;  write 2 = burst (see below)
//   0x14   STATUS        R    bit0 = single lookup done, bit1 = burst done
//   0x18   Y_OUT         R    [17:0] answer of the last single lookup (UQ0.18)
//   0x1C   LATENCY       R    clocks from the LUT taking the input to the answer coming out
//   0x20   BURST_N       R/W  burst: how many lookups, one per clock, back to back
//   0x24   BURST_STEP    R/W  burst: added to the voltage after each lookup (signed)
//   0x28   BURST_CYCLES  R    burst: clocks from the first input to the last answer
//   0x2C   BURST_SUM     R    burst: sum of all answers (wraps at 2^32), to check them all at once
//   0x30   BURST_COUNT   R    burst: number of answers that came out
//   0x34   CYCLE_COUNT   R    free-running clock counter (to measure the real clock speed)
//
// The AXI4-Lite bus (how the CPU talks to us) has 5 channels. Each one is a
// "valid / ready" handshake: the sender holds valid=1 with the data until the
// receiver says ready=1 on the same clock edge.
//   write address (aw), write data (w), write response (b)
//   read address (ar), read data (r)
// This block handles one read or one write at a time, which is all Linux needs here.
//////////////////////////////////////////////////////////////////////////////////

module lut_axi #(
    parameter CLOCK_MHZ = 100,         // only reported in INFO, so software can check it
    parameter STAGES    = 5            // which LUT version: 3, 4, 5, 6 or 7 pipeline stages
)(
    // Clock and reset. The attribute tells Vivado this clock belongs to the s_axi bus.
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET s_axi_aresetn" *)
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,  // 0 = reset

    // write address
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    // write data
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    // write response
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    // read address
    input  wire [7:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    // read data
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);

    wire clk = s_axi_aclk;

    // ---------------------------------------------------------------
    // Registers software can write
    // ---------------------------------------------------------------
    reg [26:0] v_reg;
    reg [3:0]  sel_reg;
    reg [31:0] burst_n;
    reg [31:0] burst_step;

    // one-clock "go" pulses, made when CTRL is written
    reg single_go;
    reg burst_go;

    // ---------------------------------------------------------------
    // Write channel: wait until address AND data are both valid,
    // accept them together, store the value, then send the response.
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (s_axi_aresetn == 1'b0) begin
            s_axi_awready <= 0;
            s_axi_wready  <= 0;
            s_axi_bvalid  <= 0;
            s_axi_bresp   <= 2'b00;
            v_reg         <= 0;
            sel_reg       <= 0;
            burst_n       <= 0;
            burst_step    <= 0;
            single_go     <= 0;
            burst_go      <= 0;
        end
        else begin
            // these are one-clock pulses by default
            s_axi_awready <= 0;
            s_axi_wready  <= 0;
            single_go     <= 0;
            burst_go      <= 0;

            if (s_axi_awvalid && s_axi_wvalid && !s_axi_awready && !s_axi_bvalid) begin
                s_axi_awready <= 1;          // take the address
                s_axi_wready  <= 1;          // take the data
                s_axi_bvalid  <= 1;          // and answer "OK"
                s_axi_bresp   <= 2'b00;
                case (s_axi_awaddr[7:2])     // register number = byte address / 4
                    6'h02: v_reg      <= s_axi_wdata[26:0];
                    6'h03: sel_reg    <= s_axi_wdata[3:0];
                    6'h04: begin
                               if (s_axi_wdata[0]) single_go <= 1;
                               if (s_axi_wdata[1]) burst_go  <= 1;
                           end
                    6'h08: burst_n    <= s_axi_wdata;
                    6'h09: burst_step <= s_axi_wdata;
                    default: ;               // writes to read-only registers are ignored
                endcase
            end

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 0;           // CPU took the response
            end
        end
    end

    // ---------------------------------------------------------------
    // Feeding the LUT: one input for a single lookup, or N inputs in a row
    // ---------------------------------------------------------------
    reg        lut_in_valid;
    reg [26:0] lut_v;
    reg [3:0]  lut_sel;

    reg        burst_running;
    reg [31:0] burst_left;           // inputs still to send
    reg [26:0] burst_v;              // voltage of the next burst input

    always @(posedge clk) begin
        if (s_axi_aresetn == 1'b0) begin
            lut_in_valid  <= 0;
            lut_v         <= 0;
            lut_sel       <= 0;
            burst_running <= 0;
            burst_left    <= 0;
            burst_v       <= 0;
        end
        else begin
            lut_in_valid <= 0;
            if (single_go) begin
                lut_in_valid <= 1;
                lut_v        <= v_reg;
                lut_sel      <= sel_reg;
            end
            else if (burst_go && burst_n != 0) begin
                burst_running <= 1;
                burst_left    <= burst_n;
                burst_v       <= v_reg;
            end
            else if (burst_running) begin
                lut_in_valid <= 1;
                lut_v        <= burst_v;
                lut_sel      <= sel_reg;
                burst_v      <= burst_v + burst_step[26:0];
                burst_left   <= burst_left - 1;
                if (burst_left == 1) begin
                    burst_running <= 0;      // that was the last one
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // The LUT. STAGES picks the version (same math, different pipeline depth).
    // "generate if" is like an #if in C: only the chosen one gets built.
    // ---------------------------------------------------------------
    wire        lut_out_valid;
    wire [17:0] lut_y;

    generate
        if (STAGES == 3) begin : g_lut
            lut_fixed_p3 lut (.clk(clk), .in_valid(lut_in_valid), .v_in(lut_v), .curve_sel(lut_sel),
                              .out_valid(lut_out_valid), .y_out(lut_y));
        end
        else if (STAGES == 4) begin : g_lut
            lut_fixed_p4 lut (.clk(clk), .in_valid(lut_in_valid), .v_in(lut_v), .curve_sel(lut_sel),
                              .out_valid(lut_out_valid), .y_out(lut_y));
        end
        else if (STAGES == 6) begin : g_lut
            lut_fixed_p6 lut (.clk(clk), .in_valid(lut_in_valid), .v_in(lut_v), .curve_sel(lut_sel),
                              .out_valid(lut_out_valid), .y_out(lut_y));
        end
        else if (STAGES == 7) begin : g_lut
            lut_fixed_p7 lut (.clk(clk), .in_valid(lut_in_valid), .v_in(lut_v), .curve_sel(lut_sel),
                              .out_valid(lut_out_valid), .y_out(lut_y));
        end
        else begin : g_lut
            lut_fixed    lut (.clk(clk), .in_valid(lut_in_valid), .v_in(lut_v), .curve_sel(lut_sel),
                              .out_valid(lut_out_valid), .y_out(lut_y));
        end
    endgenerate

    // ---------------------------------------------------------------
    // Measuring: latency of a single lookup, and the whole burst
    // ---------------------------------------------------------------
    reg [31:0] cycle_count;          // free-running
    reg        single_busy;
    reg        single_done;
    reg [31:0] lat_count;
    reg [31:0] latency;
    reg [17:0] y_last;

    reg        burst_busy;
    reg        burst_done;
    reg [31:0] burst_cycles;
    reg [31:0] burst_sum;
    reg [31:0] burst_count;
    reg [31:0] burst_expect;         // answers we are waiting for

    always @(posedge clk) begin
        if (s_axi_aresetn == 1'b0) begin
            cycle_count  <= 0;
            single_busy  <= 0;
            single_done  <= 0;
            lat_count    <= 0;
            latency      <= 0;
            y_last       <= 0;
            burst_busy   <= 0;
            burst_done   <= 0;
            burst_cycles <= 0;
            burst_sum    <= 0;
            burst_count  <= 0;
            burst_expect <= 0;
        end
        else begin
            cycle_count <= cycle_count + 1;

            // ---- single lookup
            if (single_go) begin
                single_done <= 0;
            end
            if (lut_in_valid && !burst_busy) begin
                // the LUT takes the input on this edge: start counting at 1
                single_busy <= 1;
                lat_count   <= 1;
            end
            else if (single_busy) begin
                if (lut_out_valid) begin
                    latency     <= lat_count;  // edges from "input taken" to "answer seen"
                    y_last      <= lut_y;
                    single_done <= 1;
                    single_busy <= 0;
                end
                else begin
                    lat_count <= lat_count + 1;
                end
            end

            // ---- burst
            if (burst_go && burst_n != 0) begin
                burst_busy   <= 1;
                burst_done   <= 0;
                burst_cycles <= 0;
                burst_sum    <= 0;
                burst_count  <= 0;
                burst_expect <= burst_n;
            end
            else if (burst_busy) begin
                // count every clock from the first input until the last answer
                if (lut_in_valid || burst_cycles != 0) begin
                    burst_cycles <= burst_cycles + 1;
                end
                if (lut_out_valid) begin
                    burst_sum   <= burst_sum + lut_y;
                    burst_count <= burst_count + 1;
                    if (burst_count + 1 == burst_expect) begin
                        burst_busy <= 0;
                        burst_done <= 1;
                    end
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // Read channel: take the address, send back the register's value
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (s_axi_aresetn == 1'b0) begin
            s_axi_arready <= 0;
            s_axi_rvalid  <= 0;
            s_axi_rdata   <= 0;
            s_axi_rresp   <= 2'b00;
        end
        else begin
            s_axi_arready <= 0;

            if (s_axi_arvalid && !s_axi_arready && !s_axi_rvalid) begin
                s_axi_arready <= 1;
                s_axi_rvalid  <= 1;
                s_axi_rresp   <= 2'b00;
                case (s_axi_araddr[7:2])
                    6'h00: s_axi_rdata <= 32'h4C555442;               // "LUTB"
                    6'h01: s_axi_rdata <= {12'd0, CLOCK_MHZ[11:0], STAGES[7:0]};
                    6'h02: s_axi_rdata <= {5'd0, v_reg};
                    6'h03: s_axi_rdata <= {28'd0, sel_reg};
                    6'h05: s_axi_rdata <= {30'd0, burst_done, single_done};
                    6'h06: s_axi_rdata <= {14'd0, y_last};
                    6'h07: s_axi_rdata <= latency;
                    6'h08: s_axi_rdata <= burst_n;
                    6'h09: s_axi_rdata <= burst_step;
                    6'h0A: s_axi_rdata <= burst_cycles;
                    6'h0B: s_axi_rdata <= burst_sum;
                    6'h0C: s_axi_rdata <= burst_count;
                    6'h0D: s_axi_rdata <= cycle_count;
                    default: s_axi_rdata <= 32'hDEADBEEF;            // unused register
                endcase
            end

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 0;            // CPU took the data
            end
        end
    end

endmodule
