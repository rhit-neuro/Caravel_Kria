# CLAUDED
# Starting point for the Kria SOM. Verify the strings in the Vivado console:
#   get_parts xck26*          get_board_parts *k26*   get_board_parts *kv260*
set target(proj_name)   caravel_kria
set target(part)        xck26-sfvc784-2LV-c
set target(board_part)  xilinx.com:kr260_som:part0:2.0
# Carrier card pin mapping. Verify with: get_property board_connections [current_project]
# after picking the KR260 board in the GUI.
set target(board_connections) {som240_1_connector xilinx.com:kr260_carrier:som240_1_connector:1.0}
set target(top)         caravel
set target(constraints) {vivado/constraints/caravel_kria.xdc}
set target(ip)          {vivado/ip/bram/bram.xci vivado/ip/clk_fix_1/clk_fix.xci}