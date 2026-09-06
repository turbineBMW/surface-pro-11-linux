@echo off
rem SPDX-License-Identifier: MIT
rem Copyright (c) 2026 turbinebmw
rem
rem Surface Pro 11 Linux: make a bootable USB stick from Windows in one go
rem (firmware collection + raw ISO write + firmware onto the stick).
rem Put this folder's files next to the downloaded ISO, then run this.

setlocal
net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
    echo Asking for administrator rights ...
    powershell.exe -NoLogo -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
    exit /b
)
echo Surface Pro 11 Linux USB creator
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0sp11-usb-creator.ps1" %*
set "sp11_exit=%ERRORLEVEL%"
echo.
if not "%sp11_exit%"=="0" (
    echo The creator stopped with exit code %sp11_exit%. Read the message above.
    echo Alternative: write the ISO with Rufus in "DD image" mode, then run
    echo RUN-IN-WINDOWS.cmd from the stick's SP11FW drive.
)
pause
exit /b %sp11_exit%
