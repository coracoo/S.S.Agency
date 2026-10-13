@echo off
REM Refresh the asset index: scan runtime-referenced assets and write back
REM to the canvas document. Paths only; never touches original assets.
REM Dry-run first to print stats, then write for real.
setlocal
cd /d "%~dp0..\.."

python tools\canvas\extract_game_assets.py --dry-run || goto :fail
python tools\canvas\extract_game_assets.py || goto :fail
echo.
echo [OK] Asset index refreshed.
exit /b 0

:fail
echo.
echo [FAIL] Refresh failed, see output above.
exit /b 1
