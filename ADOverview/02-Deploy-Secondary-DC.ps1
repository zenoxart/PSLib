
#requires -RunAsAdministrator
#requires -Version 5.1

<#
    02-Deploy-Secondary-DC.ps1

    Creates an additional Domain Controller
    in an existing Active Directory forest.

    Run once to join the domain and once after reboot
    to promote and verify the secondary DC.
#>

$ErrorActionPreference = "Stop"

# =========================================================
# LOGGING
# =========================================================

$LogDirectory = "$env:ProgramData\AD-Deployment"

New-Item -ItemType Directory `
    -Path $LogDirectory -Force | Out-Null

Start-Transcript `
    -Path "$LogDirectory\Secondary-DC.log" `
    -Append | Out-Null

# =========================================================
# ADMINISTRATOR CHECK
# =========================================================

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "Run as Administrator."
}

# =========================================================
# NETWORK DISCOVERY
# =========================================================

$Computer = Get-CimInstance Win32_ComputerSystem

$Adapter = Get-NetAdapter |
    Where-Object Status -eq "Up" |
    Select-Object -First 1

if (-not $Adapter) {
    throw "No active network adapter found."
}

$LocalAddress = Get-NetIPAddress `
    -InterfaceIndex $Adapter.ifIndex `
    -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -notlike "169.254.*"
    } |
    Select-Object -First 1

if (-not $LocalAddress) {
    throw "No valid IPv4 address found."
}

if ($LocalAddress.PrefixOrigin -eq "Dhcp") {
    throw "Configure a static IP before promoting this server."
}

Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "IP: $($LocalAddress.IPAddress)"

# =========================================================
# PRIMARY DOMAIN CONTROLLER
# =========================================================

$PrimaryDCIP = Read-Host "Enter primary Domain Controller IPv4 address"

if ($PrimaryDCIP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
    throw "Invalid IPv4 address."
}

if (-not (Test-Connection $PrimaryDCIP -Count 2 -Quiet)) {
    throw "Primary DC is not reachable."
}

# Configure DNS to use primary DC
Set-DnsClientServerAddress `
    -InterfaceIndex $Adapter.ifIndex `
    -ServerAddresses $PrimaryDCIP

Write-Host "Primary DNS configured: $PrimaryDCIP"

# =========================================================
# STAGE 1: JOIN EXISTING DOMAIN
# =========================================================

if (-not $Computer.PartOfDomain) {

    $DomainName = Read-Host "Enter existing AD domain (example: kks.local)"

    $Credential = Get-Credential `
        -Message "Enter domain administrator credentials"

    Write-Host "Joining domain $DomainName..."

    Add-Computer `
        -DomainName $DomainName `
        -Credential $Credential `
        -Restart

    Stop-Transcript | Out-Null
    exit
}

# =========================================================
# STAGE 2: PROMOTE TO SECONDARY DC
# =========================================================

$DomainName = $Computer.Domain

Import-Module ActiveDirectory

$CurrentDomain = Get-ADDomain

if ($CurrentDomain.DNSRoot -ne $DomainName) {
    throw "Domain detection mismatch."
}

if ($Computer.DomainRole -eq 4 -or $Computer.DomainRole -eq 5) {

    Write-Host "This machine is already a Domain Controller."

    # Configure DNS to prefer primary DC and use itself second
    Set-DnsClientServerAddress `
        -InterfaceIndex $Adapter.ifIndex `
        -ServerAddresses @(
            $PrimaryDCIP,
            $LocalAddress.IPAddress
        )

    Write-Host "`nReplication summary:"
    repadmin /replsummary

    Write-Host "`nDNS diagnostics:"
    dcdiag /test:dns

    Stop-Transcript | Out-Null
    exit
}

# Install AD DS
Install-WindowsFeature `
    AD-Domain-Services `
    -IncludeManagementTools

$Credential = Get-Credential `
    -Message "Enter domain administrator credentials"

$DSRMPassword = Read-Host `
    "Enter Directory Services Restore Mode password" `
    -AsSecureString

Write-Host "Promoting secondary Domain Controller..." `
    -ForegroundColor Cyan

Add-ADDSDomainController `
    -DomainName $DomainName `
    -Credential $Credential `
    -InstallDns `
    -SafeModeAdministratorPassword $DSRMPassword `
    -NoRebootOnCompletion `
    -Force

Write-Host "Promotion completed. Restarting..."

Stop-Transcript | Out-Null

Restart-Computer -Force
