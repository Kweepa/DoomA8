@echo off
setlocal
cd /d "%~dp0"

if exist "%~dp0setup-env.bat" call "%~dp0setup-env.bat"

python tools\build.py %*
exit /b %errorlevel%
