$ErrorActionPreference = 'Stop'

Write-Host 'Configuring OpenSSH Server'
Set-LocalUser -Name 'Administrator' -PasswordNeverExpires $true

$capability = Get-WindowsCapability -Online |
    Where-Object Name -Like 'OpenSSH.Server*' |
    Select-Object -First 1
if (-not $capability) {
    throw 'The OpenSSH.Server Windows capability is unavailable.'
}
if ($capability.State -ne 'Installed') {
    Write-Host 'Installing OpenSSH.Server capability'
    Add-WindowsCapability -Online -Name $capability.Name | Out-Null
} else {
    Write-Host 'OpenSSH.Server capability is already installed'
}

Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd

if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    Write-Host 'Creating OpenSSH firewall rule'
    New-NetFirewallRule `
        -Name 'OpenSSH-Server-In-TCP' `
        -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22 | Out-Null
} else {
    Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True
}

$openSshRegistry = 'HKLM:\SOFTWARE\OpenSSH'
if (-not (Test-Path $openSshRegistry)) {
    New-Item -Path $openSshRegistry -Force | Out-Null
}
New-ItemProperty `
    -Path $openSshRegistry `
    -Name DefaultShell `
    -Value "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -PropertyType String `
    -Force | Out-Null

$alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^*-_=+'
$randomBytes = New-Object byte[] 48
$randomNumberGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$randomNumberGenerator.GetBytes($randomBytes)
$randomNumberGenerator.Dispose()
$randomPassword = -join ($randomBytes | ForEach-Object {
    $alphabet[$_ % $alphabet.Length]
})
$securePassword = ConvertTo-SecureString $randomPassword -AsPlainText -Force

if (-not (Get-LocalUser -Name 'vmuser' -ErrorAction SilentlyContinue)) {
    Write-Host 'Creating vmuser local account'
    New-LocalUser `
        -Name 'vmuser' `
        -Description 'Windows sandbox SSH administrator' `
        -Password $securePassword `
        -PasswordNeverExpires `
        -UserMayNotChangePassword | Out-Null
} else {
    Write-Host 'vmuser already exists; rotating its unusable random password'
    Set-LocalUser -Name 'vmuser' -Password $securePassword -PasswordNeverExpires $true
}

$administrators = Get-LocalGroup -SID 'S-1-5-32-544'
$isAdministrator = Get-LocalGroupMember -Group $administrators |
    Where-Object Name -Match '\\vmuser$'
if (-not $isAdministrator) {
    Add-LocalGroupMember -Group $administrators -Member 'vmuser'
}

if (-not $env:SSH_PUBLIC_KEY_BASE64) {
    throw 'SSH_PUBLIC_KEY_BASE64 was not supplied by Packer.'
}
$publicKey = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($env:SSH_PUBLIC_KEY_BASE64)
).Trim()
if (-not $publicKey.StartsWith('ssh-ed25519 ')) {
    throw 'The supplied SSH public key is not an Ed25519 public key.'
}

$sshDataDirectory = Join-Path $env:ProgramData 'ssh'
$authorizedKeysPath = Join-Path $sshDataDirectory 'administrators_authorized_keys'
New-Item -ItemType Directory -Path $sshDataDirectory -Force | Out-Null
Set-Content -Path $authorizedKeysPath -Value $publicKey -Encoding ascii

Write-Host 'Restricting administrators_authorized_keys ACL'
$acl = New-Object System.Security.AccessControl.FileSecurity
$acl.SetAccessRuleProtection($true, $false)
$fullControl = [System.Security.AccessControl.FileSystemRights]::FullControl
$allow = [System.Security.AccessControl.AccessControlType]::Allow
$systemSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
$administratorsSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
$acl.AddAccessRule(
    (New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, $fullControl, $allow))
)
$acl.AddAccessRule(
    (New-Object System.Security.AccessControl.FileSystemAccessRule($administratorsSid, $fullControl, $allow))
)
Set-Acl -Path $authorizedKeysPath -AclObject $acl

$sshdConfigPath = Join-Path $sshDataDirectory 'sshd_config'
$sshdConfig = Get-Content -Path $sshdConfigPath -Raw
if ($sshdConfig -match '(?m)^\s*#?\s*PasswordAuthentication\s+') {
    $sshdConfig = $sshdConfig -replace '(?m)^\s*#?\s*PasswordAuthentication\s+.*$', 'PasswordAuthentication no'
} else {
    $sshdConfig += "`r`nPasswordAuthentication no`r`n"
}
if ($sshdConfig -match '(?m)^\s*#?\s*PubkeyAuthentication\s+') {
    $sshdConfig = $sshdConfig -replace '(?m)^\s*#?\s*PubkeyAuthentication\s+.*$', 'PubkeyAuthentication yes'
} else {
    $sshdConfig += "`r`nPubkeyAuthentication yes`r`n"
}
Set-Content -Path $sshdConfigPath -Value $sshdConfig -Encoding ascii

Restart-Service -Name sshd
Write-Host 'OpenSSH Server configuration complete'
