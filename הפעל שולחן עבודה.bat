@echo off
chcp 65001 >nul
title BRIDGE OS
cd /d "%~dp0"

echo.
echo  BRIDGE OS - שולחן העבודה
echo  מפעיל שרת... הדפדפן ייפתח אחרי שהשרת מוכן.
echo  לסגירה: סגור חלון זה.
echo.

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0bridge.ps1" start
if errorlevel 1 (
  echo.
  echo  שגיאה בהפעלה. נסה לסגור חלונות Bridge OS קודמים.
  pause
)