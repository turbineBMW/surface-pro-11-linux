@echo off
rem SPDX-License-Identifier: MIT
rem Copyright (c) 2026 turbinebmw
rem
rem Surface Pro 11 Linux: copy the firmware Linux needs from this Windows
rem installation onto the SP11FW partition of the live USB stick.

setlocal
echo Surface Pro 11 firmware collector
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0sp11-collect-firmware.ps1" -TargetSP11FW
set "sp11_exit=%ERRORLEVEL%"
echo.
if not "%sp11_exit%"=="0" (
    echo The collector failed with exit code %sp11_exit%.
    echo A list of everything it found was saved as SP11-FIRMWARE-COLLECTOR-REPORT.tsv
    echo next to this file. Include it, and this window's output, when asking for help.
    echo See FIRMWARE.md on this drive for other ways to get the files.
) else (
    echo Firmware collection completed. Safely eject the USB stick and boot from it.
)
echo.
pause
exit /b %sp11_exit%
