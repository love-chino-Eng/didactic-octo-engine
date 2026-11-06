@echo off
chcp 65001 >nul
title Reaction Game Launcher
echo ============================================
echo   Reaction Timer - download and run
echo ============================================
echo.
echo Make sure PuTTY is already open on COM7 (115200 8-N-1).
echo.
call D:\vivado\2019.1\bin\xsdb.bat D:\vivado\reaction_test\start4.tcl
echo.
echo Game started. Watch the PuTTY window.
timeout /t 5 >nul
