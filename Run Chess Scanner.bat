@echo off
rem Double-click to boot the Pixel_8 emulator (if needed) and run the app on it.
rem Keep this window open while testing: r = hot reload, R = hot restart, q = quit.
setlocal
title Chess Scanner

set "AVD=Pixel_8"
set "BOOT_TIMEOUT=240"
if defined ANDROID_HOME (set "SDK=%ANDROID_HOME%") else (set "SDK=%LOCALAPPDATA%\Android\Sdk")
set "ADB=%SDK%\platform-tools\adb.exe"
set "EMULATOR=%SDK%\emulator\emulator.exe"
rem flutter.bat needs where.exe and PowerShell. PATH can arrive with unexpanded
rem "%%SystemRoot%%\..." entries, so put the Windows folders first explicitly.
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\WindowsPowerShell\v1.0;%PATH%"
rem Silences the "restricted method in java.lang.System" warnings from Gradle.
set "JAVA_OPTS=--enable-native-access=ALL-UNNAMED"

if not exist "%ADB%" (echo adb not found at "%ADB%" & goto :fail)
if not exist "%EMULATOR%" (echo emulator not found at "%EMULATOR%" & goto :fail)
where flutter >nul 2>&1 || (echo flutter is not on PATH & goto :fail)

rem A Gradle daemon killed mid-write (window closed, VS Code's Java extension
rem shutting down) corrupts this journal and every later build dumps thousands
rem of "CorruptedCacheException" stack traces. It only tracks cache access
rem times, so it is safe to delete whenever no Gradle daemon is using it.
set "GRADLE_JOURNAL=%USERPROFILE%\.gradle\caches\journal-1"
if exist "%GRADLE_JOURNAL%" (
    powershell -NoProfile -Command "if (Get-CimInstance Win32_Process -Filter \"Name='java.exe'\" | Where-Object CommandLine -match 'GradleDaemon') { exit 1 }" >nul 2>&1
    if not errorlevel 1 rd /s /q "%GRADLE_JOURNAL%" >nul 2>&1
)

"%ADB%" start-server >nul 2>&1

rem Reuse an emulator that is already running and online.
call :find_device
if not defined DEVICE (
    echo Starting emulator %AVD% ^(cold boot^)...
    rem Cold boot: the Quick Boot snapshot has crashed this AVD before.
    start "" /min "%EMULATOR%" -avd %AVD% -no-snapshot-load
)

echo Waiting for the emulator to finish booting...
set /a WAITED=0
:waitboot
if not defined DEVICE call :find_device
set "BOOTED="
if defined DEVICE (
    for /f %%b in ('"%ADB%" -s %DEVICE% shell getprop sys.boot_completed 2^>nul') do set "BOOTED=%%b"
)
if "%BOOTED%"=="1" goto :booted
if %WAITED% geq %BOOT_TIMEOUT% (
    echo Emulator did not finish booting within %BOOT_TIMEOUT% seconds.
    echo Try a cold boot / wipe of %AVD% from Android Studio's Device Manager.
    goto :fail
)
timeout /t 2 /nobreak >nul
set /a WAITED+=2
goto :waitboot

:booted
echo %DEVICE% ready. Launching app...
cd /d "%~dp0app"
call flutter run -d %DEVICE%
goto :end

rem Sets DEVICE to the first emulator in the "device" (online) state.
:find_device
set "DEVICE="
for /f "tokens=1,2" %%d in ('"%ADB%" devices') do (
    if not defined DEVICE echo %%d| findstr /b "emulator-" >nul && if "%%e"=="device" set "DEVICE=%%d"
)
exit /b

:fail
echo.
echo Launch failed.
:end
pause
