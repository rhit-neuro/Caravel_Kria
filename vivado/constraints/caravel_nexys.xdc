# old constraints file from previous 
create_clock -period 10.000 -name clock100 [get_ports clock100]

create_clock -period 10.000 -name housekeeping_spi_clk [get_ports {mprj_io[4]}]

create_generated_clock -name clock12 clk_fix/inst/mmcm_adv_inst/CLKOUT0

set_clock_groups -asynchronous -group {clock100} -group {housekeeping_spi_clk}
set_clock_groups -asynchronous -group {clock12}  -group {housekeeping_spi_clk}

# Outputs
set_output_delay -clock clock12 -add_delay 5.000 [get_ports flash_clk]
set_output_delay -clock clock12 -add_delay 5.000 [get_ports flash_csb]

# bidirectional
set_output_delay -clock clock12 -add_delay 5.000 [get_ports flash_io0]
set_input_delay  -clock clock12 -add_delay 5.000 [get_ports flash_io0]

set_output_delay -clock clock12 -add_delay 5.000 [get_ports flash_io1]
set_input_delay  -clock clock12 -add_delay 5.000 [get_ports flash_io1]

set_output_delay -clock clock12 -add_delay 5.000 [get_ports gpio]
set_input_delay  -clock clock12 -add_delay 5.000 [get_ports gpio]

set_output_delay -clock clock12 -add_delay 5.000 [get_ports {mprj_io[*]}]
set_input_delay  -clock clock12 -add_delay 5.000 [get_ports {mprj_io[*]}]

#set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets {mprj_io_IOBUF[4]_inst/O}]
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
set_property -dict { PACKAGE_PIN D2    IOSTANDARD LVCMOS33 } [get_ports { mprj_in[25] }]; #IO_L14N_T2_SRCC_35 Sch=sd_dat[3]

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