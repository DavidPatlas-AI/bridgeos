@echo off
chcp 65001 >nul
cd /d "%~dp0"
python scripts\install_rainmeter_bridge.py
echo.
echo לחץ F5 ב-Rainmeter לרענון, או: Rainmeter ^> Refresh all
pause