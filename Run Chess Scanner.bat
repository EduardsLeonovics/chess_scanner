@echo off
rem Double-click to boot the Pixel_8 emulator (if needed) and run the app on it.
rem Keep this window open while testing: r = hot reload, R = hot restart, q = quit.
setlocal
title Chess Scanner

set "AVD=Pixel_8"
if defined ANDROID_HOME (set "SDK=%ANDROID_HOME%") else (set "SDK=%LOCALAPPDATA%\Android\Sdk")
set "ADB=%SDK%\platform-tools\adb.exe"
set "EMULATOR=%SDK%\emulator\emulator.exe"
rem flutter.bat needs where.exe and PowerShell. PATH can arrive with unexpanded
rem "%%SystemRoot%%\..." entries, so put the Windows folders first explicitly.
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\WindowsPowerShell\v1.0;%PATH%"

if not exist "%ADB%" (echo adb not found at "%ADB%" & goto :fail)
if not exist "%EMULATOR%" (echo emulator not found at "%EMULATOR%" & goto :fail)
where flutter >nul 2>&1 || (echo flutter is not on PATH & goto :fail)

"%ADB%" start-server >nul 2>&1

rem Reuse an emulator that is already running.
set "DEVICE="
for /f "tokens=1" %%d in ('"%ADB%" devices ^| findstr /b emulator-') do if not defined DEVICE set "DEVICE=%%d"

if not defined DEVICE (
    echo Starting emulator %AVD% ^(cold boot^)...
    rem Cold boot: the Quick Boot snapshot has crashed this AVD before.
    start "" /min "%EMULATOR%" -avd %AVD% -no-snapshot-load
    "%ADB%" wait-for-device
    for /f "tokens=1" %%d in ('"%ADB%" devices ^| findstr /b emulator-') do if not defined DEVICE set "DEVICE=%%d"
)
if not defined DEVICE (echo Could not find the emulator. & goto :fail)

echo Waiting for %DEVICE% to finish booting...
:waitboot
set "BOOTED="
for /f %%b in ('"%ADB%" -s %DEVICE% shell getprop sys.boot_completed 2^>nul') do set "BOOTED=%%b"
if not "%BOOTED%"=="1" (
    timeout /t 2 /nobreak >nul
    goto :waitboot
)

echo Emulator ready. Launching app...
cd /d "%~dp0app"
call flutter run -d %DEVICE%
goto :end

:fail
echo.
echo Launch failed.
:end
pause
