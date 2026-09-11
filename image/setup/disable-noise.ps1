$ErrorActionPreference = 'Stop'

Write-Host 'Applying modest background-noise reductions'

$windowsUpdatePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
New-Item -Path $windowsUpdatePath -Force | Out-Null
New-ItemProperty `
    -Path $windowsUpdatePath `
    -Name NoAutoRebootWithLoggedOnUsers `
    -Value 1 `
    -PropertyType DWord `
    -Force | Out-Null

$serverManagerPath = 'HKLM:\SOFTWARE\Microsoft\ServerManager'
New-Item -Path $serverManagerPath -Force | Out-Null
New-ItemProperty `
    -Path $serverManagerPath `
    -Name DoNotOpenServerManagerAtLogon `
    -Value 1 `
    -PropertyType DWord `
    -Force | Out-Null

Write-Host 'Disabling hibernation'
& powercfg.exe /hibernate off
if ($LASTEXITCODE -ne 0) {
    throw "powercfg.exe exited with code $LASTEXITCODE."
}

$defenderScan = Get-ScheduledTask `
    -TaskPath '\Microsoft\Windows\Windows Defender\' `
    -TaskName 'Windows Defender Scheduled Scan' `
    -ErrorAction SilentlyContinue
if ($defenderScan) {
    Write-Host 'Disabling the Defender scheduled scan task'
    Disable-ScheduledTask -InputObject $defenderScan | Out-Null
}

Write-Host 'Background-noise reductions complete'
