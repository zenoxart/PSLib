
#requires -RunAsAdministrator
#requires -Version 5.1

<#
    04-Deploy-FTP-Server.ps1

    Windows Server IIS FTP deployment.

    Features:
      - IIS FTP Server
      - Active Directory authentication
      - FTPS encryption
      - FTP user isolation
      - Passive FTP ports
      - Windows Firewall configuration
      - Logging and validation

    Run on a domain-joined member server.
#>

$ErrorActionPreference = "Stop"

# =========================================================
# ONLY USER-MAINTAINED CONFIGURATION
# =========================================================

$FtpSiteName = "AD-FTP"
$FtpRoot = "D:\FTP"

$FtpPort = 21

$PassivePortStart = 50000
$PassivePortEnd = 50100

$FtpGroupName = "FTP-Users"

$FtpDirectoryName = "LocalUser"

# Set to $true when a valid FTPS certificate is installed.
$EnableFTPS = $true

# Certificate thumbprint from LocalMachine\My.
$CertificateThumbprint = ""

# Require encrypted control and data connections.
$RequireSSL = $true

# =========================================================
# LOGGING
# =========================================================

$LogDirectory = "$env:ProgramData\AD-Deployment"

New-Item -Path $LogDirectory `
    -ItemType Directory -Force | Out-Null

Start-Transcript `
    -Path "$LogDirectory\FTP-Deployment.log" `
    -Append | Out-Null

try {

    # =====================================================
    # VALIDATION
    # =====================================================

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

    if (-not $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )) {
        throw "Run as Administrator."
    }

    $Computer = Get-CimInstance Win32_ComputerSystem

    if (-not $Computer.PartOfDomain) {
        throw "Server must be joined to an Active Directory domain."
    }

    Import-Module ActiveDirectory

    $Domain = Get-ADDomain
    $DomainDN = $Domain.DistinguishedName
    $DomainName = $Domain.DNSRoot

    Write-Host "Domain: $DomainName"

    # =====================================================
    # CERTIFICATE VALIDATION
    # =====================================================

    if ($EnableFTPS) {

        if (-not $CertificateThumbprint) {
            throw "FTPS requires a valid certificate thumbprint. Install a certificate first."
        }

        $Certificate = Get-Item `
            "Cert:\LocalMachine\My\$CertificateThumbprint" `
            -ErrorAction Stop

        if ($Certificate.NotAfter -le (Get-Date)) {
            throw "FTP certificate has expired."
        }

        if (-not $Certificate.HasPrivateKey) {
            throw "FTP certificate has no private key."
        }
    }

    # =====================================================
    # INSTALL IIS FTP COMPONENTS
    # =====================================================

    Write-Host "`nInstalling IIS FTP Server..."

    Install-WindowsFeature `
        Web-Server,
        Web-FTP-Server,
        Web-FTP-Service,
        Web-FTP-Ext `
        -IncludeManagementTools

    Import-Module WebAdministration

    # =====================================================
    # CREATE FTP GROUP
    # =====================================================

    $FtpGroup = Get-ADGroup `
        -Filter "Name -eq '$FtpGroupName'" `
        -ErrorAction SilentlyContinue

    if (-not $FtpGroup) {

        Write-Host "Creating AD group: $FtpGroupName"

        New-ADGroup `
            -Name $FtpGroupName `
            -SamAccountName $FtpGroupName `
            -GroupCategory Security `
            -GroupScope Global `
            -Path "CN=Users,$DomainDN" `
            -Description "Users allowed to access the FTP server"
    }

    # =====================================================
    # CREATE FTP DIRECTORIES
    # =====================================================

    if (-not (Test-Path $FtpRoot)) {
        New-Item -ItemType Directory -Path $FtpRoot -Force |
            Out-Null
    }

    $UserRoot = Join-Path $FtpRoot $FtpDirectoryName

    New-Item -ItemType Directory `
        -Path $UserRoot -Force | Out-Null

    # =====================================================
    # NTFS PERMISSIONS
    # =====================================================

    $Acl = Get-Acl $FtpRoot

    # Administrators: Full control
    $AdminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Administrators",
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )

    $Acl.SetAccessRule($AdminRule)

    # SYSTEM: Full control
    $SystemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NT AUTHORITY\SYSTEM",
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )

    $Acl.SetAccessRule($SystemRule)

    Set-Acl -Path $FtpRoot -AclObject $Acl

    # FTP users get access only to their own directory.
    $UserAcl = Get-Acl $UserRoot

    $UserRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$DomainNetBIOS\$FtpGroupName",
        "Modify",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )

    $UserAcl.SetAccessRule($UserRule)

    Set-Acl -Path $UserRoot -AclObject $UserAcl

    # =====================================================
    # CREATE IIS FTP SITE
    # =====================================================

    $ExistingSite = Get-Website `
        -Name $FtpSiteName `
        -ErrorAction SilentlyContinue

    if ($ExistingSite) {
        Write-Host "FTP site already exists. Updating configuration."
    }
    else {

        New-WebFtpSite `
            -Name $FtpSiteName `
            -Port $FtpPort `
            -PhysicalPath $FtpRoot `
            -Force
    }

    # =====================================================
    # FTP AUTHENTICATION
    # =====================================================

    # Disable anonymous authentication
    Set-WebConfigurationProperty `
        -PSPath "IIS:\Sites\$FtpSiteName" `
        -Filter "system.ftpServer/security/authentication/anonymousAuthentication" `
        -Name enabled `
        -Value $false

    # Enable Basic authentication
    Set-WebConfigurationProperty `
        -PSPath "IIS:\Sites\$FtpSiteName" `
        -Filter "system.ftpServer/security/authentication/basicAuthentication" `
        -Name enabled `
        -Value $true

    # =====================================================
    # FTP AUTHORIZATION
    # =====================================================

    Clear-WebConfiguration `
        -PSPath "IIS:\Sites\$FtpSiteName" `
        -Filter "system.ftpServer/security/authorization"

    Add-WebConfiguration `
        -PSPath "IIS:\Sites\$FtpSiteName" `
        -Filter "system.ftpServer/security/authorization" `
        -Value @{
            accessType = "Allow"
            roles = "$FtpGroupName"
            permissions = "Read, Write"
        }

    # =====================================================
    # FTP USER ISOLATION
    # =====================================================

    Set-WebConfigurationProperty `
        -PSPath "IIS:\Sites\$FtpSiteName" `
        -Filter "system.ftpServer/userIsolation" `
        -Name mode `
        -Value "IsolateAllDirectories"

    # =====================================================
    # PASSIVE FTP CONFIGURATION
    # =====================================================

    Set-WebConfigurationProperty `
        -PSPath "MACHINE/WEBROOT/APPHOST" `
        -Filter "system.ftpServer/firewallSupport" `
        -Name lowDataChannelPort `
        -Value $PassivePortStart

    Set-WebConfigurationProperty `
        -PSPath "MACHINE/WEBROOT/APPHOST" `
        -Filter "system.ftpServer/firewallSupport" `
        -Name highDataChannelPort `
        -Value $PassivePortEnd

    # =====================================================
    # FTPS CONFIGURATION
    # =====================================================

    if ($EnableFTPS) {

        Set-ItemProperty `
            -Path "IIS:\Sites\$FtpSiteName" `
            -Name ftpServer.security.ssl.controlChannelPolicy `
            -Value "SslRequire"

        Set-ItemProperty `
            -Path "IIS:\Sites\$FtpSiteName" `
            -Name ftpServer.security.ssl.dataChannelPolicy `
            -Value "SslRequire"

        Set-ItemProperty `
            -Path "IIS:\Sites\$FtpSiteName" `
            -Name ftpServer.security.ssl.serverCertHash `
            -Value $CertificateThumbprint

    }
    else {

        Set-ItemProperty `
            -Path "IIS:\Sites\$FtpSiteName" `
            -Name ftpServer.security.ssl.controlChannelPolicy `
            -Value "SslAllow"

        Set-ItemProperty `
            -Path "IIS:\Sites\$FtpSiteName" `
            -Name ftpServer.security.ssl.dataChannelPolicy `
            -Value "SslAllow"
    }

    # =====================================================
    # FIREWALL
    # =====================================================

    $FirewallRules = @(
        @{
            Name = "FTP-Control"
            Port = "$FtpPort"
        },
        @{
            Name = "FTP-Passive"
            Port = "$PassivePortStart-$PassivePortEnd"
        }
    )

    foreach ($Rule in $FirewallRules) {

        $ExistingRule = Get-NetFirewallRule `
            -DisplayName $Rule.Name `
            -ErrorAction SilentlyContinue

        if (-not $ExistingRule) {

            New-NetFirewallRule `
                -DisplayName $Rule.Name `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort $Rule.Port `
                -Action Allow `
                -Profile Domain
        }
    }

    # =====================================================
    # FTP SERVICE
    # =====================================================

    Set-Service FTPSVC -StartupType Automatic

    Start-Service FTPSVC

    Restart-WebItem "IIS:\Sites\$FtpSiteName"

    # =====================================================
    # VALIDATION
    # =====================================================

    Write-Host "`n=== FTP SITE ==="

    Get-Website -Name $FtpSiteName |
        Format-List Name, State, PhysicalPath

    Write-Host "`n=== FTP AUTHENTICATION ==="

    Get-WebConfiguration `
        -PSPath "IIS:\Sites\$FtpSiteName" `
        -Filter "system.ftpServer/security/authentication/*" |
        Format-List

    Write-Host "`n=== FIREWALL RULES ==="

    Get-NetFirewallRule |
        Where-Object DisplayName -like "FTP-*" |
        Format-Table DisplayName, Enabled, Profile

    Write-Host "`nFTP deployment completed." `
        -ForegroundColor Green

    Write-Host "FTP root: $FtpRoot"
    Write-Host "Domain: $DomainName"
    Write-Host "FTP group: $FtpGroupName"

}
catch {

    Write-Host "`nERROR: $($_.Exception.Message)" `
        -ForegroundColor Red

    throw

}
finally {

    Stop-Transcript | Out-Null

}
