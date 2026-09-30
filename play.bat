@echo off
REM === Launch game (no editor) ===
REM Double-click this file to play.

set "GODOT=J:\godot\Godot_v4.6.3-stable_win64.exe"
set "PROJECT=J:\godot\S.S.Agency"

if not exist "%GODOT%" (
    echo [ERROR] Godot engine not found: %GODOT%
    pause
    exit /b 1
)

if not exist "%PROJECT%\project.godot" (
    echo [ERROR] project.godot not found: %PROJECT%
    pause
    exit /b 1
)

"%GODOT%" --path "%PROJECT%"

if errorlevel 1 (
    echo.
    echo [Game exited with error code %errorlevel%]
    pause
)
