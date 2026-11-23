@echo off
setlocal
cd /d "%~dp0"

REM build-gbc.bat        -> gbc\build\doomgbc.gbc
REM build-gbc.bat test   -> gbc\build\doomgbc_test.gbc (headless screenshot check)
REM build-gbc.bat bench  -> gbc\build\doomgbc_bench.gbc (timing run, see tools\gbc_bench.py)

if exist "%~dp0setup-env.bat" call "%~dp0setup-env.bat"
if not defined RGBDS set "RGBDS=C:\dev\tools\rgbds"
if not exist "%RGBDS%\rgbasm.exe" (
  echo RGBDS not found at %RGBDS% - set RGBDS in setup-env.bat
  exit /b 1
)

set "DEFS="
set "NAME=doomgbc"
if /i "%~1"=="test" (
  set "DEFS=-D TEST_EXIT=1"
  set "NAME=doomgbc_test"
)
if /i "%~1"=="bench" (
  set "DEFS=-D TEST_EXIT=1 -D BENCH=1"
  set "NAME=doomgbc_bench"
)

if not exist gbc\build mkdir gbc\build

python tools\gbc_font.py gbc\build\font.inc
if errorlevel 1 exit /b 1
python tools\gbc_genlines.py gbc\build
if errorlevel 1 exit /b 1

set "OBJS="
for %%F in (main vars line fb bench) do (
  "%RGBDS%\rgbasm.exe" -Weverything %DEFS% -I gbc\ -I gbc\build\ -o gbc\build\%%F.o gbc\%%F.asm
  if errorlevel 1 exit /b 1
  call set "OBJS=%%OBJS%% gbc\build\%%F.o"
)

"%RGBDS%\rgblink.exe" -m gbc\build\%NAME%.map -n gbc\build\%NAME%.sym -o gbc\build\%NAME%.gbc %OBJS%
if errorlevel 1 exit /b 1

REM CGB-only, MBC5+RAM+BATTERY, 8 KB SRAM, pad with $FF to a valid ROM size.
"%RGBDS%\rgbfix.exe" -v -C -m 0x1B -r 2 -p 0xFF -t DOOMGBC gbc\build\%NAME%.gbc
if errorlevel 1 exit /b 1

echo Built gbc\build\%NAME%.gbc
exit /b 0
