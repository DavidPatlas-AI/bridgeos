@echo off
chcp 65001 >nul
cd /d "%~dp0"
title BridgeOS Health Check
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\audit_bridgeos.ps1"
echo.
echo Report: BRIDGE_HEALTH_REPORT.md
pause
