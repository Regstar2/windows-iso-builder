@echo off
setlocal
cd /d "%~dp0"

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo Windows PowerShell 5.1 was not found.
    echo Run this tool on Windows 10 or Windows 11.
    echo.
    pause
    exit /b 9009
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Builder.ps1"
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" echo Windows ISO Builder finished with exit code %RC%.
pause
exit /b %RC%
