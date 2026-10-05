@echo off
setlocal
REM The project follows this launcher; GODOT_BIN can select any installed engine explicitly.
set "PROJECT=%~dp0."
set "SCENE=res://scenes/campaign/title.tscn"
set "GODOT="
if defined GODOT_BIN (
    if not exist "%GODOT_BIN%" (
        echo [ERROR] GODOT_BIN does not point to an existing engine: %GODOT_BIN%
        pause
        exit /b 1
    )
    set "GODOT=%GODOT_BIN%"
)
REM Prefer the user-reported version beside this project or in the previous engine directory.
for %%G in ("%~dp0Godot_v4.7.2-stable_win64.exe" "%~dp0..\Godot_v4.7.2-stable_win64.exe" "J:\godot\Godot_v4.7.2-stable_win64.exe" "J:\godot\Godot_v4.7.2-stable_win64_console.exe") do if not defined GODOT if exist "%%~G" set "GODOT=%%~fG"
for /f "delims=" %%G in ('where godot.exe 2^>nul') do if not defined GODOT set "GODOT=%%G"
REM Keep the validated previous engine as an explicit fallback, without installing anything.
for %%G in ("%~dp0..\Godot_v4.6.3-stable_win64.exe" "J:\godot\Godot_v4.6.3-stable_win64.exe") do if not defined GODOT if exist "%%~G" set "GODOT=%%~fG"
if not defined GODOT (
    echo [ERROR] Godot was not found. Set GODOT_BIN to your installed Godot executable.
    pause
    exit /b 1
)
if not exist "%PROJECT%\project.godot" (
    echo [ERROR] project.godot was not found beside this launcher.
    pause
    exit /b 1
)
echo [Godot] %GODOT%
"%GODOT%" --path "%PROJECT%" "%SCENE%"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
    echo [Game exited with error code %RESULT%]
    pause
)
exit /b %RESULT%
