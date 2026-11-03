@echo off
rem AI citation: created with Claude Opus 5.5 by Anthropic (via Claude Code), 2026-11-01 to 2026-11-03.
rem run_sim.bat -- simulate the AXI register block + LUT in xsim.
rem     run_sim.bat        (5-stage LUT)
rem     run_sim.bat 7      (7-stage LUT; also 3, 4, 6)
cd /d %~dp0
set VBIN=C:\AMDDesignTools\2026.1\Vivado\bin
set ST=%1
if "%ST%"=="" set ST=5
if exist xsim.dir\work rmdir /s /q xsim.dir\work
rem tell the testbench the stage count (xvlog.bat mangles "-d NAME=value", so use a file)
> tb_stages.vh echo `define STAGES %ST%
call %VBIN%\xvlog.bat ..\rtl\lut_fixed.v ..\rtl\lut_fixed_p3.v ..\rtl\lut_fixed_p4.v ..\rtl\lut_fixed_p6.v ..\rtl\lut_fixed_p7.v ..\rtl\lut_axi.v tb_lut_axi.v || exit /b 1
call %VBIN%\xelab.bat tb_lut_axi -debug off -s snap_axi || exit /b 1
call %VBIN%\xsim.bat snap_axi -runall
