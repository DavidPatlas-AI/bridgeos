@echo off
chcp 65001 >nul
cd /d "%~dp0.."
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0..\bridge.ps1" open p7
pause