@echo off
chcp 65001 >nul
cd /d "%~dp0"
title BridgeOS package
echo.
echo Creating BridgeOS portable package...
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\package_bridge.ps1"
if errorlevel 1 (
  echo.
  echo Package failed. Close open ZIP files and try again.
  pause
  exit /b 1
)
echo.
echo Ready: dist\BridgeOS-portable.zip
pause
