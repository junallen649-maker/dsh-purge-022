@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
if errorlevel 1 echo [FAILED] see the messages above.
echo Press any key to close...
pause >nul
