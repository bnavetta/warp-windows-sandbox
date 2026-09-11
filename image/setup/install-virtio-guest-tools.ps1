$ErrorActionPreference = 'Stop'

Write-Host 'Locating virtio-win guest tools'

$installer = Get-Volume |
    Where-Object DriveLetter |
    ForEach-Object {
        Join-Path "$($_.DriveLetter):\" 'virtio-win-guest-tools.exe'
    } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if (-not $installer) {
    throw 'virtio-win-guest-tools.exe was not found on any mounted volume.'
}

$installedVersion = Get-ItemProperty `
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', `
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
    -ErrorAction SilentlyContinue |
    Where-Object DisplayName -Like 'Virtio-win-guest-tools*' |
    Select-Object -First 1

if ($installedVersion) {
    Write-Host "Virtio guest tools are already installed: $($installedVersion.DisplayVersion)"
} else {
    Write-Host "Installing virtio guest tools from $installer"
    $process = Start-Process `
        -FilePath $installer `
        -ArgumentList '/install', '/quiet', '/norestart' `
        -Wait `
        -PassThru
    if ($process.ExitCode -notin 0, 3010) {
        throw "Virtio guest tools installer exited with code $($process.ExitCode)."
    }
}

if (Get-Service -Name 'qemu-ga' -ErrorAction SilentlyContinue) {
    Set-Service -Name 'qemu-ga' -StartupType Automatic
    Start-Service -Name 'qemu-ga'
}

Write-Host 'Virtio guest tools configuration complete'
