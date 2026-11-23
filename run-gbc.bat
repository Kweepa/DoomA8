@echo off
setlocal
cd /d "%~dp0"

if exist "%~dp0setup-env.bat" call "%~dp0setup-env.bat"
if not defined GBEMU set "GBEMU=C:\dev\tools\bgb\bgb64.exe"

set "ROM=%~dp0gbc\build\doomgbc.gbc"
if not exist "%ROM%" (
  echo %ROM% missing - run build-gbc.bat first
  exit /b 1
)
if not exist "%GBEMU%" (
  echo BGB not found at %GBEMU% - set GBEMU in setup-env.bat
  exit /b 1
)
start "" "%GBEMU%" "%ROM%"
