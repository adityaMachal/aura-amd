@echo off
title Aura-AMD Launcher

echo ===================================================
echo   Aura-AMD: Local AI Acceleration Control Room
echo ===================================================
echo.
echo Initializing portable environments and verifying models...
echo This may take a few minutes on the first run.
echo.

REM The magic flag here is -ExecutionPolicy Bypass.
REM This prevents Windows from blocking the script on the judge's machine.
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0startup.ps1"

REM If the script crashes or closes unexpectedly, pause so the user can read the error.
pause
