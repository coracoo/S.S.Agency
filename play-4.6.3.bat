@echo off
REM === Launch game (no editor) ===
REM Double-click this file to play.
REM 默认使用 project.godot 中的正式标题入口。
REM 临时预览其他场景时可设置 SCENE；留空按项目配置启动。

set "GODOT=%~dp0..\Godot_v4.6.3-stable_win64.exe"
set "PROJECT=%~dp0."
set "SCENE="

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
