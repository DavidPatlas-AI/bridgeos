@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Bridge OS — שכבת חוטים שקופה
echo.
echo מפעיל שכבת חוטים שקופה על שולחן העבודה...
echo סגירה: Esc · כפתור ✕ בתחתית · סגור overlay.bat
echo.
start "" pythonw "%~dp0bridge_overlay.pyw"
timeout /t 2 >nul
echo הופעל ברקע (pythonw)
echo.