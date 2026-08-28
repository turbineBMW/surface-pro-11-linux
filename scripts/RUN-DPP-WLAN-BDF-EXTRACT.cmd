@echo off
setlocal
title SP11 read-only DPP WLAN extractor

fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting Administrator access...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -Verb RunAs -ArgumentList '/c','\"%~f0\"'"
    exit /b
)

cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sp11-extract-dpp-wlan-bdf.ps1"
set "extract_status=%errorlevel%"
echo.
if not "%extract_status%"=="0" (
    echo The extractor stopped with an error. Copy the new result directory back to Linux.
) else (
    echo Done. Copy the new SP11-DPP-WLAN-BDF-RESULT-* directory back to Linux.
)
pause
exit /b %extract_status%

