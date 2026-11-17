@echo off
rem AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-01 to 2026-11-03.
rem run_sim.bat -- compile and run the LUT testbench in Vivado's simulator (xsim).
rem Run from this folder:
rem     run_sim.bat                  tests lut_fixed     (5 stages)
rem     run_sim.bat lut_fixed_p3     tests lut_fixed_p3  (3 stages), same for p4 / p6 / p7
rem Make the .mem files first:  python ..\model\gen_fixed_lut.py .
rem Work in the folder this .bat file is in, wherever it was started from.
cd /d %~dp0
set VBIN=C:\AMDDesignTools\2026.1\Vivado\bin
set TOP=%1
if "%TOP%"=="" set TOP=lut_fixed
if exist xsim.dir\work rmdir /s /q xsim.dir\work
rem Tell the testbench which module to test (xvlog.bat mangles "-d NAME=value", so use a file).
echo `define LUT_TOP %TOP%> lut_top.vh
call %VBIN%\xvlog.bat ..\rtl\%TOP%.v tb_lut_fixed.v || exit /b 1
call %VBIN%\xelab.bat tb_lut_fixed -debug off -s snap_%TOP% || exit /b 1
call %VBIN%\xsim.bat snap_%TOP% -runall
