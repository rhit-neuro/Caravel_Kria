@echo off
rem AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-09.
rem run_bank_sim.bat -- xsim of the 9-gate bank (rtau_bank_s6), RTL or gate level.
rem     run_bank_sim.bat <W> <samples> <ram_block>                    RTL
rem     run_bank_sim.bat <W> <samples> <ram_block> <netlist_funcsim.v>  gate level (latency = 6 + 2)
cd /d %~dp0
set VBIN=C:\AMDDesignTools\2026.1\Vivado\bin
if exist xsim.dir\work rmdir /s /q xsim.dir\work
> cfgb.vh echo `define W %1
>> cfgb.vh echo `define NSAMP %2
>> cfgb.vh echo `define RAM_BLOCK %3
>> cfgb.vh echo `include "tbb_w%1_n%2.vh"
if "%4"=="" goto rtl
>> cfgb.vh echo `define NETLIST
call %VBIN%\xvlog.bat %4 tb_rtau_bank.v C:\AMDDesignTools\2026.1\Vivado\data\verilog\src\glbl.v || exit /b 1
call %VBIN%\xelab.bat tb_rtau_bank glbl -L unisims_ver -L secureip -debug off -s snap_bankg || exit /b 1
call %VBIN%\xsim.bat snap_bankg -runall
goto :eof
:rtl
call %VBIN%\xvlog.bat ..\rtl\rtau_gate_s6.v ..\rtl\rtau_bank_s6.v tb_rtau_bank.v || exit /b 1
call %VBIN%\xelab.bat tb_rtau_bank -debug off -s snap_bank || exit /b 1
call %VBIN%\xsim.bat snap_bank -runall
