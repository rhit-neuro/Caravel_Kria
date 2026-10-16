`timescale 1ns / 1ps
`include "defines.v"
//////////////////////////////////////////////////////////////////////////////////
// Company: Team 08
// Engineer: Ben McDaniel, Josh Schrock
// 
// Create Date: 10/30/2024 10:00:13 AM
// Module Name: TopLevel.v
// Description: Toplevel Userspace for Caravel project.
// 
// 
//////////////////////////////////////////////////////////////////////////////////


module TopLevel #(
    parameter BITS = 32
)(


//Part of Actual Userspace Def, not needed for our implementation
//`ifdef USE_POWER_PINS
//    inout vdda1,	// User area 1 3.3V supply
//    inout vdda2,	// User area 2 3.3V supply
//    inout vssa1,	// User area 1 analog ground
//    inout vssa2,	// User area 2 analog ground
//    inout vccd1,	// User area 1 1.8V supply
//    inout vccd2,	// User area 2 1.8v supply
//    inout vssd1,	// User area 1 digital ground
//    inout vssd2,	// User area 2 digital ground
//`endif

    // Wishbone Device ports (WB MI A)
    input wire wb_clk_i,
    input wire wb_rst_i,
    input wire wbs_stb_i,
    input wire wbs_cyc_i,
    input wire wbs_we_i,
    input wire [3:0] wbs_sel_i,
    input wire [31:0] wbs_dat_i,
    input wire [31:0] wbs_adr_i,
    output reg wbs_ack_o,
    output reg [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  wire [127:0] la_data_in,
    output wire [127:0] la_data_out,
    input  wire [127:0] la_oenb,


// TODO- Understand and implement these
//    // IOs
    input wire [`MPRJ_IO_PADS-1:0] io_in,
    output wire [`MPRJ_IO_PADS-1:0] io_out,
    output wire [`MPRJ_IO_PADS-1:0] io_oeb,

    // Analog (direct connection to GPIO pad---use with caution)
    // Note that analog I/O is not available on the 7 lowest-numbered
    // GPIO pads, and so the analog_io indexing is offset from the
    // GPIO indexing by 7 (also upper 2 GPIOs do not have analog_io).
    inout wire [`MPRJ_IO_PADS-10:0] analog_io,


//Temp def of IOs, REPLACE WITH ABOVE
    //TODO

    // Independent clock (on independent integer divider)
    input wire user_clock2,

    // User maskable interrupt signals
    output wire [2:0] user_irq
);

//Assign Address Space
//this will be the top 8 bits of the address
localparam [11:0] ADDR_MEMORY = 12'h300,
                 ADDR_DMA = 12'h304,
                 ADDR_LUT = 12'h305,
                 ADDR_SD = 12'h306,
                 ADDR_SYNAPTIC = 12'h307;

//Userspace Wishbone wires (B4 wishbone, DMA controlled)
wire usr_wb_clk = wb_clk_i; //same clock for now
wire usr_wb_rst = wb_rst_i; //same reset for now
wire usr_wb_cyc;
wire usr_wb_stb;
wire usr_wb_we;
reg usr_wb_ack;  
reg usr_wb_stall; 
wire [31:0] usr_wb_adr;
reg [31:0] usr_wb_dat_mi;
wire [31:0] usr_wb_dat_mo;
wire [3:0] usr_wb_sel;
wire usr_wb_err;
assign usr_wb_adr[1:0] = 2'b00;
   
//Set unused wires to 0
assign la_data_out[127:4] = 0;
assign io_oeb = 0;
assign analog_io = 0;
assign io_out[`MPRJ_IO_PADS-1:3] = 0;
assign user_irq[2:1] = 0;

//SD wires
wire sd_int_o;
//wire sd_bus_grant_i; // whether or not we can use the SPI port
wire [31:0] sd_debug_o; // wires for debugging sd

//DMA wires
wire [31:0] usr_dma_ints_i = 0;    //no DMA interrupts for now

//Assign Strobes for Wishbone
//Management Strobes (B3, from CORE)
reg mem3_stb;
reg dma_stb;
reg lut3_stb;
        
always @(*)
    case(wbs_adr_i[31:20])
    ADDR_MEMORY: begin
        mem3_stb <= wbs_stb_i;
        dma_stb <= 0;
        lut3_stb <= 0;
        end
    ADDR_DMA: begin
        mem3_stb <= 0;
        dma_stb <= wbs_stb_i;
        lut3_stb <= 0;
        end 
    ADDR_LUT: begin
        mem3_stb <= 0;
        dma_stb <= 0;
        lut3_stb <= wbs_stb_i;
        end 
    default: begin
        mem3_stb <= 0;
        dma_stb <= 0;
        lut3_stb <= 0;
        end 
    endcase
            
//Userspace Strobes (B4, from DMA)
reg mem4_stb;
reg lut4_stb;
reg sd_stb;
reg synaptic_stb;
        
always @(*)
    case(usr_wb_adr[31:20])
    ADDR_MEMORY: begin
        mem4_stb <= usr_wb_stb;
        lut4_stb <= 0;
        sd_stb <= 0;
        synaptic_stb <= 0;
        end
    ADDR_LUT: begin
        mem4_stb <= 0;
        lut4_stb <= usr_wb_stb;
        sd_stb <= 0;
        synaptic_stb <= 0;
        end 
    ADDR_SD: begin
        mem4_stb <= 0;
        lut4_stb <= 0;
        sd_stb <= usr_wb_stb;
        synaptic_stb <= 0;
        end 
    ADDR_SYNAPTIC: begin
        mem4_stb <= 0;
        lut4_stb <= 0;
        sd_stb <= 0;
        synaptic_stb <= usr_wb_stb;
        end  
    default: begin
        mem4_stb <= 0;
        lut4_stb <= 0;
        sd_stb <= 0;
        synaptic_stb <= 0;
        end 
    endcase

//assign wishbone B3 ack and data
wire mem_ack_3, dma_ack_3, lut_ack_3;
wire [31:0] mem_dat_3, dma_dat_3, lut_dat_3;

always @(*)
    case(wbs_adr_i[31:20])
    ADDR_MEMORY: begin
        wbs_ack_o <= mem_ack_3;
        wbs_dat_o <= mem_dat_3;
        end
    ADDR_DMA: begin
        wbs_ack_o <= dma_ack_3;
        wbs_dat_o <= dma_dat_3;
        end 
    ADDR_LUT: begin
        wbs_ack_o <= lut_ack_3;
        wbs_dat_o <= lut_dat_3;
        end 
    default: begin
        wbs_ack_o <= 1'b0;
        wbs_dat_o <= 32'b0;
        end 
    endcase
    
//assign wishbone B4 ack, stall, and data 
wire mem_ack_4, lut_ack_4, sd_ack_4, syn_ack_4;
wire mem_stall_4, lut_stall_4, sd_stall_4, syn_stall_4;
wire [31:0] mem_dat_4, lut_dat_4, sd_dat_4, syn_dat_4;
  
always @(*)
    case(usr_wb_adr[31:20])
    ADDR_MEMORY: begin
        usr_wb_ack <= mem_ack_4;
        usr_wb_stall <= mem_stall_4;
        usr_wb_dat_mi <= mem_dat_4;
        end
    ADDR_LUT: begin
        usr_wb_ack <= lut_ack_4;
        usr_wb_stall <= lut_stall_4;
        usr_wb_dat_mi <= lut_dat_4;
        end 
    ADDR_SD: begin
        usr_wb_ack <= sd_ack_4;
        usr_wb_stall <= sd_stall_4;
        usr_wb_dat_mi <= sd_dat_4;
        end 
    ADDR_SYNAPTIC: begin
        usr_wb_ack <= syn_ack_4;
        usr_wb_stall <= syn_stall_4;
        usr_wb_dat_mi <= syn_dat_4;
        end  
    default: begin
        usr_wb_ack <= 1'b0;
        usr_wb_stall <= 1'b0;
        usr_wb_dat_mi <= 32'b0;
        end 
    endcase

 
//Internal Module Defs

// Remove Syscon for testing for now
//UserSpaceWBSYSCON SYSCON(
//    .CLK_IN(user_clock2),
//    .Reset(usr_wb_rst),
//    .WB_CLK(usr_wb_clk)
//);

zipdma DMA(

//Management Space WB (B3 peripheral)
.i_clk(wb_clk_i), .i_reset(wb_rst_i), .i_swb_cyc(wbs_cyc_i), .i_swb_stb(dma_stb), 
.i_swb_we(wbs_we_i), .i_swb_addr(wbs_adr_i[3:2]), .i_swb_data(wbs_dat_i), .i_swb_sel(wbs_sel_i), 
.o_swb_ack(dma_ack_3), .o_swb_data(dma_dat_3),

//User Space WB (B4 Controller)
   .o_mwb_cyc(usr_wb_cyc),
   .o_mwb_stb(usr_wb_stb),
   .o_mwb_we(usr_wb_we),
   .o_mwb_addr(usr_wb_adr[31:2]),
   .o_mwb_data(usr_wb_dat_mo),
   .o_mwb_sel(usr_wb_sel),
   .i_mwb_stall(usr_wb_stall),
   .i_mwb_ack(usr_wb_ack),
   .i_mwb_data(usr_wb_dat_mi),
   .i_mwb_err(usr_wb_err),
   .i_dev_ints(usr_dma_ints_i),

//Interrupt to CPU
   .o_interrupt(user_irq[0])
);


memory_intf Mem(
    .clock(wb_clk_i), .reset(wb_rst_i),
    
    ////wishbone B3 peripheral - processor
    .wb3_cyc_i(wbs_cyc_i), .wb3_stb_i(mem3_stb), .wb3_we_i(wbs_we_i),
    .wb3_adr_i(wbs_adr_i),
    .wb3_sel_i(wbs_sel_i),
    .wb3_dat_i(wbs_dat_i),
    .wb3_dat_o(mem_dat_3),
    .wb3_ack_o(mem_ack_3),
    
    //wishbone B4 peripheral - DMA
    .wb4_cyc_i(usr_wb_cyc), .wb4_stb_i(mem4_stb), .wb4_we_i(usr_wb_we),
    .wb4_adr_i(usr_wb_adr),
    .wb4_sel_i(usr_wb_sel),
    .wb4_dat_i(usr_wb_dat_mo),
    .wb4_dat_o(mem_dat_4),
    .wb4_ack_o(mem_ack_4), .wb4_stall_o(mem_stall_4), .wb4_err_o(usr_wb_err)
);


sdspi SD(

//User Space WB
   .i_clk(usr_wb_clk),
   .i_sd_reset(usr_wb_rst),
   .i_wb_cyc(usr_wb_cyc),
   .i_wb_stb(sd_stb),
   .i_wb_we(usr_wb_we),
   .i_wb_addr(usr_wb_adr[4:3]),
   .i_wb_data(usr_wb_dat_mo),
   .i_wb_sel(usr_wb_sel),
   .o_wb_stall(sd_stall_4),
   .o_wb_ack(sd_ack_4),
   .o_wb_data(sd_dat_4),
   
//SD etc
    .o_cs_n(io_out[25]), //padframe output
    .o_sck(io_out[26]), //padframe output
    .o_mosi(io_out[27]), //padframe output
    .i_miso(io_in[28]), //padframe input
    .i_card_detect(io_in[29]), //padframe input
    .o_int(sd_int_o),
	.i_bus_grant(1'b1), //set high because spi bus isn't shared
	.o_debug(sd_debug_o)
);


//SynapticModule SynMod(.Clock(user_clock2),  .irq(user_irq[1]),

////User Space WB
//    .ADR_I(usr_wb_adr),
//    .DAT_I(usr_wb_dat_mo),
//    .DAT_O(syn_dat_4),
//    .WE_I(usr_wb_we),
//    .SEL_I(usr_wb_sel),
//    .STB_I(usr_wb_stb),
//    .ACK_O(syn_ack_4),
//    .CYC_I(usr_wb_cyc),
//    .RST_I(usr_wb_rst),
//    .CLK_I(usr_wb_clk)
//);


LUT_Module LUT(
.clock(wb_clk_i), .reset(wb_rst_i),

////wishbone B3 peripheral - processor
.wb3_cyc_i(wbs_cyc_i), .wb3_stb_i(lut3_stb), .wb3_we_i(wbs_we_i),
.wb3_adr_i(wbs_adr_i),
.wb3_sel_i(wbs_sel_i),
.wb3_dat_i(wbs_dat_i),
.wb3_dat_o(lut_dat_3),
.wb3_ack_o(lut_ack_3),

//wishbone B4 peripheral - DMA
.wb4_cyc_i(usr_wb_cyc), .wb4_stb_i(lut4_stb), .wb4_we_i(usr_wb_we),
.wb4_adr_i(usr_wb_adr),
.wb4_sel_i(usr_wb_sel),
.wb4_dat_i(usr_wb_dat_mo),
.wb4_dat_o(lut_dat_4),
.wb4_ack_o(lut_ack_4), .wb4_stall_o(lut_stall_4), .wb4_err_o(usr_wb_err),

//Error Diagnostic Wires
.Exception(la_data_out[0]), .Invalid(la_data_out[1]), .Overflow(la_data_out[2]), .Underflow(la_data_out[3])
);


endmodule
