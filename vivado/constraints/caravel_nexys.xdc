#==============================================================================
# caravel_nexys.xdc 
# (clauded from here to Pin assignments)
# NOTE: the flash_clk port is a dummy; the real clock goes through STARTUPE2.
#==============================================================================

#------------------------------------------------------------------------------
# Tunables (ns)
#------------------------------------------------------------------------------
set hk_sck_period      100.0   ;# 10 MHz, as in the upstream SDC. Use your host's real max SCK.
set hk_host_tco_max    15.0    ;# >>> VERIFY host + board delay on SDI/CSB
set hk_host_tco_min    0.0
set hk_host_tsu        10.0    ;# >>> VERIFY host setup on SDO incl. board
set hk_host_th         0.0
set io_in_max          10.0
set io_in_min          0.0
set io_out_max         10.0
set io_out_min         -2.0
set flash_tsu          3.0     ;# >>> VERIFY all flash numbers (S25FL128S datasheet)
set flash_th           3.0
set flash_tv_max       8.0
set flash_tho_min      2.0
set flash_trace_max    0.3
set flash_trace_min    0.1
set flash_cclk_dly_max 6.7     ;# STARTUPE2 CCLK delay, Artix-7 max
set flash_cclk_dly_min 0.5

#------------------------------------------------------------------------------
# Clocks
#------------------------------------------------------------------------------
create_clock -name clock100 -period 10.000 [get_ports clock100]
# clk_out1_clk_fix (12 MHz) is derived automatically from the MMCM.

create_clock -name housekeeping_spi_clk -period $hk_sck_period [get_ports {mprj_io[4]}]

# GPIO serial-chain clocks: serial_clock / serial_load are muxes of these flop
# outputs (select = serial_bb_enable), clocking the 500 non-clocked gpio regs.
# Periods: pre = 2 x 83.333 ns; bit-bang ones are software-driven (slow, arbitrary).
# Generated clocks on the flop outputs, sourced from each flop's own clock pin
# (a primary clock created downstream of another clock is what TIMING-2/TIMING-4 flagged).
# -divide_by 2 is the fastest toggle rate (conservative). >>> VERIFY pin names with get_pins -hier *serial_*_reg/C
create_generated_clock -name hk_serial_clk_pre  -source [get_pins chip_core/housekeeping/serial_clock_pre_reg/C] -divide_by 2 [get_pins chip_core/housekeeping/serial_clock_pre_reg/Q]
create_generated_clock -name hk_serial_clk_bb   -source [get_pins chip_core/housekeeping/serial_bb_clock_reg/C]  -divide_by 2 [get_pins chip_core/housekeeping/serial_bb_clock_reg/Q]
create_generated_clock -name hk_serial_load_pre -source [get_pins chip_core/housekeeping/serial_load_pre_reg/C]  -divide_by 2 [get_pins chip_core/housekeeping/serial_load_pre_reg/Q]
create_generated_clock -name hk_serial_load_bb  -source [get_pins chip_core/housekeeping/serial_bb_load_reg/C]   -divide_by 2 [get_pins chip_core/housekeeping/serial_bb_load_reg/Q]

# QSPI flash clock leaves through STARTUPE2/USRCCLKO. Worst case = core clock / 2.
# >>> VERIFY this command takes effect (flash_sck must appear in report_clocks).
create_generated_clock -name flash_sck -source [get_pins clk_fix/inst/mmcm_adv_inst/CLKOUT0] -divide_by 2 [get_pins STARTUPE2/USRCCLKO]

#------------------------------------------------------------------------------
# Asynchronous domains (same structure as the Caravel signoff SDC)
#------------------------------------------------------------------------------
set_clock_groups -asynchronous -group [get_clocks {clk_out1_clk_fix flash_sck}] -group [get_clocks housekeeping_spi_clk] -group [get_clocks hk_serial_clk_pre] -group [get_clocks hk_serial_clk_bb] -group [get_clocks hk_serial_load_pre] -group [get_clocks hk_serial_load_bb]

#------------------------------------------------------------------------------
# Housekeeping SPI I/O (mprj_io[1]=SDO, [2]=SDI, [3]=CSB, [4]=SCK)
#------------------------------------------------------------------------------
set_input_delay  -clock housekeeping_spi_clk -clock_fall -max $hk_host_tco_max [get_ports {mprj_io[2] mprj_io[3]}]
set_input_delay  -clock housekeeping_spi_clk -clock_fall -min $hk_host_tco_min [get_ports {mprj_io[2] mprj_io[3]}]
set_output_delay -clock housekeeping_spi_clk -max $hk_host_tsu                 [get_ports {mprj_io[1]}]
set_output_delay -clock housekeeping_spi_clk -min [expr -$hk_host_th]          [get_ports {mprj_io[1]}]
# Unused directions of these bidirectional pads
set_false_path -from [get_ports {mprj_io[1]}]
set_false_path -to   [get_ports {mprj_io[2] mprj_io[3] mprj_io[4]}]

#------------------------------------------------------------------------------
# Generic GPIO vs core clock (explicit port list: mprj_io[0], [5..37], gpio)
#------------------------------------------------------------------------------
set_input_delay  -clock clk_out1_clk_fix -max $io_in_max  [get_ports {mprj_io[0] mprj_io[5] mprj_io[6] mprj_io[7] mprj_io[8] mprj_io[9] mprj_io[10] mprj_io[11] mprj_io[12] mprj_io[13] mprj_io[14] mprj_io[15] mprj_io[16] mprj_io[17] mprj_io[18] mprj_io[19] mprj_io[20] mprj_io[21] mprj_io[22] mprj_io[23] mprj_io[24] mprj_io[25] mprj_io[26] mprj_io[27] mprj_io[28] mprj_io[29] mprj_io[30] mprj_io[31] mprj_io[32] mprj_io[33] mprj_io[34] mprj_io[35] mprj_io[36] mprj_io[37] gpio}]
set_input_delay  -clock clk_out1_clk_fix -min $io_in_min  [get_ports {mprj_io[0] mprj_io[5] mprj_io[6] mprj_io[7] mprj_io[8] mprj_io[9] mprj_io[10] mprj_io[11] mprj_io[12] mprj_io[13] mprj_io[14] mprj_io[15] mprj_io[16] mprj_io[17] mprj_io[18] mprj_io[19] mprj_io[20] mprj_io[21] mprj_io[22] mprj_io[23] mprj_io[24] mprj_io[25] mprj_io[26] mprj_io[27] mprj_io[28] mprj_io[29] mprj_io[30] mprj_io[31] mprj_io[32] mprj_io[33] mprj_io[34] mprj_io[35] mprj_io[36] mprj_io[37] gpio}]
set_output_delay -clock clk_out1_clk_fix -max $io_out_max [get_ports {mprj_io[0] mprj_io[5] mprj_io[6] mprj_io[7] mprj_io[8] mprj_io[9] mprj_io[10] mprj_io[11] mprj_io[12] mprj_io[13] mprj_io[14] mprj_io[15] mprj_io[16] mprj_io[17] mprj_io[18] mprj_io[19] mprj_io[20] mprj_io[21] mprj_io[22] mprj_io[23] mprj_io[24] mprj_io[25] mprj_io[26] mprj_io[27] mprj_io[28] mprj_io[29] mprj_io[30] mprj_io[31] mprj_io[32] mprj_io[33] mprj_io[34] mprj_io[35] mprj_io[36] mprj_io[37] gpio}]
set_output_delay -clock clk_out1_clk_fix -min $io_out_min [get_ports {mprj_io[0] mprj_io[5] mprj_io[6] mprj_io[7] mprj_io[8] mprj_io[9] mprj_io[10] mprj_io[11] mprj_io[12] mprj_io[13] mprj_io[14] mprj_io[15] mprj_io[16] mprj_io[17] mprj_io[18] mprj_io[19] mprj_io[20] mprj_io[21] mprj_io[22] mprj_io[23] mprj_io[24] mprj_io[25] mprj_io[26] mprj_io[27] mprj_io[28] mprj_io[29] mprj_io[30] mprj_io[31] mprj_io[32] mprj_io[33] mprj_io[34] mprj_io[35] mprj_io[36] mprj_io[37] gpio}]

#------------------------------------------------------------------------------
# QSPI flash I/O vs flash_sck
# >>> VERIFY: after a run, check hold with
#     report_timing -delay_type min -to [get_ports {flash_csb flash_io0 flash_io1}]
#------------------------------------------------------------------------------
set_output_delay -clock flash_sck -max [expr $flash_tsu + $flash_trace_max - $flash_trace_min] [get_ports {flash_csb flash_io0 flash_io1}]
set_output_delay -clock flash_sck -min [expr $flash_trace_min - $flash_th - $flash_trace_max]  [get_ports {flash_csb flash_io0 flash_io1}]
set_input_delay  -clock flash_sck -max [expr $flash_cclk_dly_max + $flash_tv_max + $flash_trace_max] [get_ports {flash_io0 flash_io1}]
set_input_delay  -clock flash_sck -min [expr $flash_cclk_dly_min + $flash_tho_min + $flash_trace_min] [get_ports {flash_io0 flash_io1}]
set_false_path -to [get_ports flash_clk]

#------------------------------------------------------------------------------
# Human-timescale / static I/O
#------------------------------------------------------------------------------
set_false_path -from [get_ports FPGA_rst]
set_false_path -to   [get_ports {Display[*] Transistors[*]}]

#==============================================================================
# Pin assignments (unchanged from caravel_nexys.xdc)
#==============================================================================
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clock100 }]
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports { FPGA_rst }]
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { gpio     }]

##Quad SPI Flash
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { flash_io0 }]; #IO_L1P_T0_D00_MOSI_14 Sch=qspi_dq[0]
set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports { flash_io1 }]; #IO_L1N_T0_D01_DIN_14 Sch=qspi_dq[1]
# These pins arent used by our flash controller bc we don't do full qspi
#set_property -dict { PACKAGE_PIN L14   IOSTANDARD LVCMOS33 } [get_ports { QSPI_DQ[2] }]; #IO_L2P_T0_D02_14 Sch=qspi_dq[2]
#set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { QSPI_DQ[3] }]; #IO_L2N_T0_D03_14 Sch=qspi_dq[3] 
set_property -dict { PACKAGE_PIN L13   IOSTANDARD LVCMOS33 } [get_ports { flash_csb }]; #IO_L6P_T0_FCS_B_14 Sch=qspi_csn
set_property -dict {                   IOSTANDARD LVCMOS33 } [get_ports { flash_clk }]
# clock is handled by STARTUPE2 module

##CPU SPI Pins (PMOD JD) 
set_property -dict { PACKAGE_PIN H4    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[32] }]; #spi_sck
set_property -dict { PACKAGE_PIN H1    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[33] }]; #spi_csb
set_property -dict { PACKAGE_PIN G1    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[34] }]; #spi_sdi (poci)
set_property -dict { PACKAGE_PIN G3    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[35] }]; #spi_sdo (pico)
set_property -dict { PACKAGE_PIN H2    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[36] }]; #flash_io2
set_property -dict { PACKAGE_PIN G4    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[37] }]; #flash_io3

# CPU SPI Pins
# #set_property -dict { PACKAGE_PIN E2    IOSTANDARD LVCMOS33 } [get_ports { SD_RESET }]; #IO_L14P_T2_SRCC_35 Sch=sd_reset
# set_property -dict { PACKAGE_PIN A1    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[34] }]; #IO_L9N_T1_DQS_AD7N_35 Sch=sd_cd
# set_property -dict { PACKAGE_PIN B1    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[31] }]; #IO_L9P_T1_DQS_AD7P_35 Sch=sd_sck
# set_property -dict { PACKAGE_PIN C1    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[32] }]; #IO_L16N_T2_35 Sch=sd_cmd
# set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[33] }]; #IO_L16P_T2_35 Sch=sd_dat[0]
# #set_property -dict { PACKAGE_PIN E1    IOSTANDARD LVCMOS33 } [get_ports { SD_DAT[1] }]; #IO_L18N_T2_35 Sch=sd_dat[1]
# #set_property -dict { PACKAGE_PIN F1    IOSTANDARD LVCMOS33 } [get_ports { SD_DAT[2] }]; #IO_L18P_T2_35 Sch=sd_dat[2]
# set_property -dict { PACKAGE_PIN D2    IOSTANDARD LVCMOS33 } [get_ports { mprj_in[30] }]; #IO_L14N_T2_SRCC_35 Sch=sd_dat[3]

# SDSPI Pins to Micro SD card
#set_property -dict { PACKAGE_PIN E2    IOSTANDARD LVCMOS33 } [get_ports { SD_RESET }]; #IO_L14P_T2_SRCC_35 Sch=sd_reset
set_property -dict { PACKAGE_PIN A1    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[29] }]; #IO_L9N_T1_DQS_AD7N_35 Sch=sd_cd
set_property -dict { PACKAGE_PIN B1    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[26] }]; #IO_L9P_T1_DQS_AD7P_35 Sch=sd_sck
set_property -dict { PACKAGE_PIN C1    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[27] }]; #IO_L16N_T2_35 Sch=sd_cmd
set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[28] }]; #IO_L16P_T2_35 Sch=sd_dat[0]
#set_property -dict { PACKAGE_PIN E1    IOSTANDARD LVCMOS33 } [get_ports { SD_DAT[1] }]; #IO_L18N_T2_35 Sch=sd_dat[1]
#set_property -dict { PACKAGE_PIN F1    IOSTANDARD LVCMOS33 } [get_ports { SD_DAT[2] }]; #IO_L18P_T2_35 Sch=sd_dat[2]
set_property -dict { PACKAGE_PIN D2    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[25] }]; #IO_L14N_T2_SRCC_35 Sch=sd_dat[3]

# 7 Segment Display Pins Below
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { Display[0] }]; #IO_L24N_T3_A00_D16_14 Sch=ca
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports { Display[1] }]; #IO_25_14 Sch=cb
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { Display[2] }]; #IO_25_15 Sch=cc
set_property -dict { PACKAGE_PIN K13   IOSTANDARD LVCMOS33 } [get_ports { Display[3] }]; #IO_L17P_T2_A26_15 Sch=cd
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { Display[4] }]; #IO_L13P_T2_MRCC_14 Sch=ce
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { Display[5] }]; #IO_L19P_T3_A10_D26_14 Sch=cf
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { Display[6] }]; #IO_L4P_T0_D04_14 Sch=cg
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { Display[7] }]; #IO_L19N_T3_A21_VREF_15 Sch=dp
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { Transistors[0] }]; #IO_L23P_T3_FOE_B_15 Sch=an[0]
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { Transistors[1] }]; #IO_L23N_T3_FWE_B_15 Sch=an[1]
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { Transistors[2] }]; #IO_L24P_T3_A01_D17_14 Sch=an[2]
set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports { Transistors[3] }]; #IO_L19P_T3_A22_15 Sch=an[3]
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { Transistors[4] }]; #IO_L8N_T1_D12_14 Sch=an[4]
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { Transistors[5] }]; #IO_L14P_T2_SRCC_14 Sch=an[5]
set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports { Transistors[6] }]; #IO_L23P_T3_35 Sch=an[6]
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { Transistors[7] }]; #IO_L23N_T3_A02_D18_14 Sch=an[7]

# Housekeeping SPI
##Pmod Header JA
set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33 } [get_ports { mprj_io[1] }]; #SDO       #IO_L20N_T3_A19_15 Sch=ja[1]
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { mprj_io[2] }]; #SDI       #IO_L21N_T3_DQS_A18_15 Sch=ja[2]
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports { mprj_io[3] }]; #CSB       #IO_L21P_T3_DQS_15 Sch=ja[3]
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { mprj_io[4] }]; #SCK       #IO_L18N_T2_A23_15 Sch=ja[4]
set_property -dict { PACKAGE_PIN D17   IOSTANDARD LVCMOS33 } [get_ports { mprj_io[0] }]; #JTAG      #IO_L16N_T2_A27_15 Sch=ja[7]
set_property -dict { PACKAGE_PIN E17   IOSTANDARD LVCMOS33 } [get_ports { mprj_io[5] }]; #ser_rx    #IO_L16P_T2_A28_15 Sch=ja[8]
set_property -dict { PACKAGE_PIN F18   IOSTANDARD LVCMOS33 } [get_ports { mprj_io[6] }]; #ser_tx    #IO_L22N_T3_A16_15 Sch=ja[9]
#set_property -dict { PACKAGE_PIN G18   IOSTANDARD LVCMOS33 } [get_ports { JA[10] }]; #IO_L22P_T3_A17_15 Sch=ja[10]

#Misc IO pins
# set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { mprj_io[12] }]
# set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33 } [get_ports { mprj_io[13] }]
# set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { mprj_io[14] }]
# set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports { mprj_io[15] }]
# set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { mprj_io[16] }]
# set_property -dict { PACKAGE_PIN E7    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[17] }]
# set_property -dict { PACKAGE_PIN J3    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[18] }]
# set_property -dict { PACKAGE_PIN J4    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[19] }]
# set_property -dict { PACKAGE_PIN E6    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[20] }]
# set_property -dict { PACKAGE_PIN H4    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[21] }]
# set_property -dict { PACKAGE_PIN H1    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[22] }]
# set_property -dict { PACKAGE_PIN G1    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[23] }]
# set_property -dict { PACKAGE_PIN G3    IOSTANDARD LVCMOS33 } [get_ports { mprj_io[24] }]

# set_property MARK_DEBUG false [get_nets clock_core]


# set_property MARK_DEBUG false [get_nets {chip_core/mprj_io_out[1]}]
# set_property MARK_DEBUG false [get_nets {chip_core/mprj_io_in[2]}]
# set_property MARK_DEBUG false [get_nets {chip_core/mprj_io_in[4]}]
# set_property MARK_DEBUG false [get_nets {chip_core/mprj_io_out[0]}]
# set_property MARK_DEBUG false [get_nets {chip_core/mprj_io_out[5]}]
# set_property MARK_DEBUG false [get_nets {chip_core/mprj_io_out[3]}]
# set_property MARK_DEBUG false [get_nets chip_core/clk_out1]
# set_property MARK_DEBUG false [get_nets {chip_core/mprj/user_io_out[0]}]
# set_property MARK_DEBUG false [get_nets {chip_core/mprj/user_io_out[1]}]
# set_property MARK_DEBUG false [get_nets {chip_core/mprj/user_io_out[2]}]
# set_property MARK_DEBUG false [get_nets chip_core/mprj/TopLevel/DMA/u_mm2s/usr_wb_cyc]