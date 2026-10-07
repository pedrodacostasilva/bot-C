@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALAR.ps1"
if errorlevel 1 (
  echo.
  echo Instalacao terminou com erro.
  pause
)
endlocal
