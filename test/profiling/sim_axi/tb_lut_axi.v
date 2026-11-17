// AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-01 to 2026-11-03.
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_lut_axi.v -- testbench for lut_axi.v (the register block Linux will use).
//
// Acts like the CPU: does AXI reads and writes with the two tasks below,
// the same way the board test script will use the registers.
//   1. reads ID and INFO
//   2. 4044 single lookups (every 8th test vector), checks Y_OUT and LATENCY
//   3. 4 bursts, checks BURST_SUM, BURST_COUNT and BURST_CYCLES
//////////////////////////////////////////////////////////////////////////////////
`include "tb_axi_params.vh"
`include "tb_stages.vh"

module tb_lut_axi;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;

    // AXI signals (the testbench drives the "CPU" side)
    reg  [7:0]  awaddr = 0;  reg awvalid = 0;  wire awready;
    reg  [31:0] wdata  = 0;  reg wvalid  = 0;  wire wready;
    wire [1:0]  bresp;       wire bvalid;      reg bready = 0;
    reg  [7:0]  araddr = 0;  reg arvalid = 0;  wire arready;
    wire [31:0] rdata;       wire [1:0] rresp; wire rvalid; reg rready = 0;

    lut_axi #(.CLOCK_MHZ(600), .STAGES(`STAGES)) dut (
        .s_axi_aclk(clk), .s_axi_aresetn(rstn),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(4'hF), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready)
    );

    // ---- CPU write: like  regs[addr/4] = data;
    task axi_write(input [7:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            awaddr <= addr; awvalid <= 1;
            wdata  <= data; wvalid  <= 1;
            bready <= 1;
            @(posedge clk);
            while (!(awready && wready)) @(posedge clk);
            awvalid <= 0; wvalid <= 0;
            while (!bvalid) @(posedge clk);
            @(posedge clk);
            bready <= 0;
        end
    endtask

    // ---- CPU read: like  data = regs[addr/4];
    task axi_read(input [7:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            araddr <= addr; arvalid <= 1; rready <= 1;
            @(posedge clk);
            while (!arready) @(posedge clk);
            arvalid <= 0;
            while (!rvalid) @(posedge clk);
            data = rdata;
            @(posedge clk);
            rready <= 0;
        end
    endtask

    reg [31:0] single_tv [0:2*`N_SINGLE-1];    // pairs: {sel, v}, expected y
    reg [31:0] burst_tv  [0:5*`N_BURST-1];     // v0, step, n, sel, expected sum
    reg [31:0] r;
    reg [31:0] v_word, y_exp;
    integer i, errors, lat_errors, wait_count;

    initial begin
        $readmemh("single_tests.mem", single_tv);
        $readmemh("burst_tests.mem", burst_tv);
        errors = 0;
        lat_errors = 0;

        repeat (5) @(posedge clk);
        rstn <= 1;
        repeat (5) @(posedge clk);

        // ---- 1. ID and INFO
        axi_read(8'h00, r);
        $display("ID   = %h (expect 4c555442)", r);
        if (r !== 32'h4C555442) errors = errors + 1;
        axi_read(8'h04, r);
        $display("INFO = %h (expect %h: 600 MHz, %0d stages)", r, {12'd0, 12'd600, 8'd`STAGES}, `STAGES);
        if (r !== {12'd0, 12'd600, 8'd`STAGES}) errors = errors + 1;

        // ---- 2. single lookups
        for (i = 0; i < `N_SINGLE; i = i + 1) begin
            v_word = single_tv[2*i];
            y_exp  = single_tv[2*i + 1];
            axi_write(8'h08, {5'd0, v_word[26:0]});    // V_IN
            axi_write(8'h0C, {28'd0, v_word[30:27]});  // CURVE_SEL
            axi_write(8'h10, 32'd1);                   // CTRL: go
            wait_count = 0;
            r = 0;
            while (r[0] == 0 && wait_count < 50) begin   // poll STATUS
                axi_read(8'h14, r);
                wait_count = wait_count + 1;
            end
            axi_read(8'h18, r);                        // Y_OUT
            if (r[17:0] !== y_exp[17:0]) begin
                errors = errors + 1;
                if (errors < 10) $display("SINGLE MISMATCH %0d: v=%h got %h expected %h", i, v_word, r, y_exp);
            end
            axi_read(8'h1C, r);                        // LATENCY
            if (r != `STAGES) lat_errors = lat_errors + 1;
        end
        axi_read(8'h1C, r);
        $display("single lookups: %0d done, %0d wrong answers, %0d wrong latencies, LATENCY = %0d",
                 `N_SINGLE, errors, lat_errors, r);

        // ---- 3. bursts
        for (i = 0; i < `N_BURST; i = i + 1) begin
            axi_write(8'h08, burst_tv[5*i]);          // start voltage
            axi_write(8'h24, burst_tv[5*i + 1]);      // step
            axi_write(8'h20, burst_tv[5*i + 2]);      // N
            axi_write(8'h0C, burst_tv[5*i + 3]);      // curve
            axi_write(8'h10, 32'd2);                  // CTRL: burst
            r = 0;
            while (r[1] == 0) axi_read(8'h14, r);
            axi_read(8'h2C, r);
            if (r !== burst_tv[5*i + 4]) begin
                errors = errors + 1;
                $display("BURST %0d SUM MISMATCH: got %h expected %h", i, r, burst_tv[5*i + 4]);
            end
            axi_read(8'h30, r);
            if (r !== burst_tv[5*i + 2]) errors = errors + 1;
            axi_read(8'h28, r);
            $display("burst %0d: N=%0d  BURST_CYCLES=%0d (expect N+STAGES)  sum ok=%0d",
                     i, burst_tv[5*i + 2], r, (errors == 0));
            if (r != burst_tv[5*i + 2] + `STAGES) errors = errors + 1;
        end

        // ---- free-running counter moves
        axi_read(8'h34, r);
        $display("CYCLE_COUNT = %0d", r);

        if (errors == 0 && lat_errors == 0) $display("PASS");
        else                                $display("FAIL: %0d errors, %0d latency errors", errors, lat_errors);
        $finish;
    end

endmodule
