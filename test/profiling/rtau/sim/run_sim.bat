@echo off
rem AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-09.
rem run_sim.bat -- compile and run the 1/tau LUT testbench in xsim, one configuration.
rem     run_sim.bat <module> <W: 18 or 32> <samples: 128 or 256> <ram_block: 1 or 0>
rem     e.g.  run_sim.bat rtau_lut_s6 32 256 1
rem Make the .mem/.vh files first:  python ..\model\gen_rtau_cfg.py .
cd /d %~dp0
set VBIN=C:\AMDDesignTools\2026.1\Vivado\bin
if exist xsim.dir\work rmdir /s /q xsim.dir\work
rem xvlog.bat mangles "-d NAME=value", so the settings go in a file instead
> cfg.vh echo `define LUT_TOP %1
>> cfg.vh echo `define W %2
>> cfg.vh echo `define NSAMP %3
>> cfg.vh echo `define RAM_BLOCK %4
>> cfg.vh echo `include "tb_w%2_n%3.vh"
call %VBIN%\xvlog.bat ..\rtl\%1.v tb_rtau_cfg.v || exit /b 1
call %VBIN%\xelab.bat tb_rtau_cfg -debug off -s snap_cfg || exit /b 1
call %VBIN%\xsim.bat snap_cfg -runall
