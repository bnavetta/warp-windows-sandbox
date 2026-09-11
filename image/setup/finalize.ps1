$ErrorActionPreference = 'Stop'

Write-Host 'Cleaning temporary files'
$temporaryPaths = @(
    (Join-Path $env:TEMP '*'),
    (Join-Path $env:SystemRoot 'Temp\*')
)
foreach ($path in $temporaryPaths) {
    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
}

$optimizeVolume = Get-Command Optimize-Volume -ErrorAction SilentlyContinue
if ($optimizeVolume) {
    Write-Host 'Issuing a ReTrim for drive C'
    Optimize-Volume -DriveLetter C -ReTrim -Verbose
} else {
    Write-Host 'Optimize-Volume is unavailable; skipping ReTrim'
}

Write-Host 'Rearming the Windows Server evaluation period'
# This must remain the final operation in the final provisioner. Packer performs
# the shutdown, and the rearm takes effect on the next boot. Do not reboot here.
& cscript.exe //B "$env:SystemRoot\System32\slmgr.vbs" /rearm
