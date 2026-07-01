@echo off
chcp 65001 >nul
cd /d "%~dp0"
title BridgeOS guide
start "" powershell -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File "%~dp0bridge.ps1" -Action serve
timeout /t 2 >nul
start "" "http://127.0.0.1:8787/landing.html"
