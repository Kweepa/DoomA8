@echo off
setlocal
cd /d "%~dp0"

REM build-gbc.bat        -> doomgbc.gbc (project root, committed)
REM build-gbc.bat test   -> gbc\build\doomgbc_test.gbc (headless screenshot check)
REM build-gbc.bat bench  -> gbc\build\doomgbc_bench.gbc (timing run, see tools\gbc_bench.py)
REM build-gbc.bat live   -> gbc\build\doomgbc_live.gbc (demo that stops after 3 frames; tools\gbc_check.py --live)
REM build-gbc.bat pose   -> gbc\build\doomgbc_pose.gbc (render checksums, see tools\gbc_posetest.py)

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
if /i "%~1"=="live" (
  set "DEFS=-D LIVETEST=1"
  set "NAME=doomgbc_live"
)
if /i "%~1"=="map" (
  set "DEFS=-D TEST_EXIT=1 -D MAPTEST=1"
  set "NAME=doomgbc_map"
)
if /i "%~1"=="move" (
  set "DEFS=-D TEST_EXIT=1 -D MOVETEST=1"
  set "NAME=doomgbc_move"
)
if /i "%~1"=="world" (
  set "DEFS=-D TEST_EXIT=1 -D WORLDTEST=1"
  set "NAME=doomgbc_world"
)
if /i "%~1"=="ent" (
  set "DEFS=-D TEST_EXIT=1 -D ENTTEST=1"
  set "NAME=doomgbc_ent"
)
if /i "%~1"=="smoke" (
  set "DEFS=-D TEST_EXIT=1 -D SMOKE=1"
  set "NAME=doomgbc_smoke"
)
if /i "%~1"=="pick" (
  set "DEFS=-D TEST_EXIT=1 -D PICKUNIT=1"
  set "NAME=doomgbc_pick"
)
if /i "%~1"=="comb" (
  set "DEFS=-D TEST_EXIT=1 -D COMBUNIT=1"
  set "NAME=doomgbc_comb"
)
if /i "%~1"=="los" (
  set "DEFS=-D TEST_EXIT=1 -D LOSUNIT=1"
  set "NAME=doomgbc_los"
)
if /i "%~1"=="pose" (
  set "DEFS=-D TEST_EXIT=1 -D POSETEST=1"
  set "NAME=doomgbc_pose"
)

REM Release ROM goes to the project root (tracked); test variants stay in gbc\build.
set "OUT=gbc\build\%NAME%.gbc"
if /i "%NAME%"=="doomgbc" set "OUT=doomgbc.gbc"

if defined GBC_DEFS set "DEFS=%DEFS% %GBC_DEFS%"
if not exist gbc\build mkdir gbc\build

python tools\gbc_a8const.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_hudfont.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_font.py gbc\build\font.inc
if errorlevel 1 exit /b 1
python tools\gbc_genlines.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_room.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_genmap.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_genworld.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_genent.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_genobj.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_genwpn.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_genwpntab.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_gensound.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_game.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_genmenu.py gbc\build
if errorlevel 1 exit /b 1
python tools\gbc_genmusic.py gbc\build
if errorlevel 1 exit /b 1

set "OBJS="
for %%F in (main vars line fb bench math render posetest data input world collide doors entity objects wpn combat ai hud player level sound menu music) do (
  "%RGBDS%\rgbasm.exe" -Weverything %DEFS% -I gbc\ -I gbc\build\ -o gbc\build\%%F.o gbc\%%F.asm
  if errorlevel 1 exit /b 1
  call set "OBJS=%%OBJS%% gbc\build\%%F.o"
)

"%RGBDS%\rgblink.exe" -m gbc\build\%NAME%.map -n gbc\build\%NAME%.sym -o %OUT% %OBJS%
if errorlevel 1 exit /b 1

REM CGB-only, MBC5+RAM+BATTERY, 8 KB SRAM, pad with $FF to a valid ROM size.
"%RGBDS%\rgbfix.exe" -v -C -m 0x1B -r 2 -p 0xFF -t DOOMGBC %OUT%
if errorlevel 1 exit /b 1

echo Built %OUT%
exit /b 0
