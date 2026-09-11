$ErrorActionPreference = 'Stop'

Write-Host 'Enabling Remote Desktop'

$terminalServerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
Set-ItemProperty -Path $terminalServerPath -Name fDenyTSConnections -Value 0

$rdpTcpPath = Join-Path $terminalServerPath 'WinStations\RDP-Tcp'
Set-ItemProperty -Path $rdpTcpPath -Name UserAuthentication -Value 1

Get-NetFirewallRule -DisplayGroup 'Remote Desktop' |
    Set-NetFirewallRule -Enabled True

Write-Host 'Remote Desktop is enabled with Network Level Authentication'
