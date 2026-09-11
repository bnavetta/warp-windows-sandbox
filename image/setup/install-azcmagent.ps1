$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host 'Installing Azure Connected Machine agent'

$agentPath = Join-Path $env:ProgramFiles 'AzureConnectedMachineAgent\azcmagent.exe'
if (Test-Path $agentPath) {
    Write-Host 'Azure Connected Machine agent is already installed'
} else {
    $msiPath = Join-Path $env:TEMP 'AzureConnectedMachineAgent.msi'
    Write-Host 'Downloading Azure Connected Machine agent MSI'
    Invoke-WebRequest `
        -Uri 'https://aka.ms/AzureConnectedMachineAgent' `
        -OutFile $msiPath `
        -UseBasicParsing

    Write-Host 'Installing Azure Connected Machine agent MSI'
    $process = Start-Process `
        -FilePath 'msiexec.exe' `
        -ArgumentList '/i', "`"$msiPath`"", '/qn', '/norestart' `
        -Wait `
        -PassThru
    if ($process.ExitCode -notin 0, 3010) {
        throw "Azure Connected Machine agent installer exited with code $($process.ExitCode)."
    }
    Remove-Item -Path $msiPath -Force -ErrorAction SilentlyContinue
}

# Phase 2 runtime hooks connect only when every required ARC_* variable is set.
# Keep the agent dormant in Phase 1 so the evaluation image has no Arc identity.
$himds = Get-Service -Name 'himds' -ErrorAction SilentlyContinue
if ($himds) {
    if ($himds.Status -ne 'Stopped') {
        Stop-Service -Name 'himds' -Force
    }
    Set-Service -Name 'himds' -StartupType Disabled
}

Write-Host 'Azure Connected Machine agent is installed and disabled'
