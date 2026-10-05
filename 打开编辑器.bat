@echo off
set "GODOT=J:\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot 4.7.2 not found: %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --editor --path "%~dp0."
