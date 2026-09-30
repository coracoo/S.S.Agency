@echo off
REM === Launch game (no editor) ===
REM Double-click this file to play.
REM 默认直达：参道舞台（2.5D 探索 + v3 凛音动画体验入口）
REM 想进主入口（标题屏）或其他场景：把下面的 SCENE 改为空串或其他 res:// 场景路径

set "GODOT=J:\godot\Godot_v4.6.3-stable_win64.exe"
set "PROJECT=J:\godot\S.S.Agency"
set "SCENE=res://scenes/v3/stage_mountain.tscn"

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

if "%SCENE%"=="" (
    "%GODOT%" --path "%PROJECT%"
) else (
    "%GODOT%" --path "%PROJECT%" "%SCENE%"
)

if errorlevel 1 (
    echo.
    echo [Game exited with error code %errorlevel%]
    pause
)
