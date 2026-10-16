# CLAUDED
# Known-good target.
set target(proj_name)   caravel_nexys
set target(part)        xc7a100tcsg324-1
set target(board_part)  digilentinc.com:nexys-a7-100t:part0:1.2
set target(top)         caravel
set target(constraints) {vivado/constraints/caravel_nexys.xdc}
set target(ip)          {vivado/ip/bram/bram.xci vivado/ip/clk_fix_1/clk_fix.xci}