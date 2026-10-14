# CLAUDED
# Starting point for the Kria SOM. Verify the strings in the Vivado console:
#   get_parts xck26*          get_board_parts *k26*   get_board_parts *kv260*
set_property -name "board_part" -value "xilinx.com:kr260_som:part0:2.0" -objects $obj
set_property -name "board_connections" -value "som240_1_connector xilinx.com:kr260_carrier:som240_1_connector:2.0 som240_2_connector xilinx.com:kr260_carrier:som240_2_connector:2.0" -objects $obj
set target(top)         caravel
set target(constraints) {vivado/constraints/caravel_kria.xdc}
# The existing .xci files were made for a 7-series part; they get upgraded on
# import, but you may want per-target copies (vivado/ip/kria/...) once they diverge.
set target(ip)          {vivado/ip/bram/bram.xci vivado/ip/clk_fix_1/clk_fix.xci}