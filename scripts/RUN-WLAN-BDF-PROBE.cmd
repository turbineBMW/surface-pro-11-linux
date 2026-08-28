@echo off
rem SPDX-License-Identifier: MIT
rem Copyright (c) 2026 turbinebmw

setlocal
title Surface Pro 11 WLAN BDF probe
echo Surface Pro 11 WLAN board-data selection probe
echo.
echo This launcher has two phases:
echo   1. Inventory Windows and arm a one-boot Process Monitor trace.
echo   2. After reboot, extract Qualcomm firmware file accesses to SP11FW.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0sp11-wlan-bdf-probe.ps1" -Mode Auto
set "sp11_exit=%ERRORLEVEL%"
echo.
if not "%sp11_exit%"=="0" (
    echo The WLAN BDF probe failed with exit code %sp11_exit%.
    echo Do not delete C:\ProgramData\SP11-WLAN-BDF-PROBE.
) else (
    echo The current probe phase completed successfully.
)
echo.
pause
exit /b %sp11_exit%
