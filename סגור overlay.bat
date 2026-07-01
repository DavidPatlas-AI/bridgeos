@echo off
chcp 65001 >nul
if exist "%~dp0.overlay.pid" (
  for /f %%p in (%~dp0.overlay.pid) do taskkill /PID %%p /F >nul 2>&1
  del "%~dp0.overlay.pid" >nul 2>&1
)
for /f "tokens=2" %%p in ('wmic process where "commandline like '%%bridge_overlay.pyw%%'" get processid 2^>nul ^| findstr /r "[0-9]"') do taskkill /PID %%p /F >nul 2>&1
echo שכבת החוטים נסגרה
timeout /t 2 >nul