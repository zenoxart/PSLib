
#Requires -RunAsAdministrator

# ============================================================
# WINDOWS SERVER 2025
# COMPLETE DEPARTMENT FTP / SMB DEPLOYMENT
# ============================================================

$ErrorActionPreference = "Stop"

# ============================================================
# 1. CONFIGURATION - EDIT THIS SECTION
# ============================================================

$ServerIP = "192.168.1.10"
$ServerName = $env:COMPUTERNAME
$Domain = (Get-CimInstance Win32_ComputerSystem).Domain

$FtpSite = "DepartmentFTP"
$FtpDNSName = "ftp.intern.example.local"

$ShareRoot = "D:\shares"
$FtpRoot = "D:\FTP-Root"
$BackupRoot = "D:\FTP-Backup"

$FtpPort = 21
$PassiveLow = 50000
$PassiveHigh = 50100

$Years = 2025..2030

$Departments = @(
    @{
        Name = "IT"
        Users = @("ftp_it01", "ftp_it02")
    },
    @{
        Name = "Finance"
        Users = @("ftp_fin01")
    },
    @{
        Name = "HR"
        Users = @("ftp_hr01")
    },
    @{
        Name = "Marketing"
        Users = @("ftp_mark01")
    }
)

$LocalGroupPrefix = "FTP_"
$ADGroupPrefix = "GG_FS_"

# SAFETY SETTINGS
$ResetDepartmentACLs = $true
$CreateSelfSignedCertificate = $true

$AppCmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"

# ============================================================
# 2. VALIDATION
# ============================================================

Write-Host "`n[1/15] VALIDATION" -ForegroundColor Cyan

if (-not (Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
    throw "Server must be domain joined."
}

if (-not (Test-Path "D:\")) {
    throw "Drive D: not found."
}

if (-not (Get-Module -ListAvailable ActiveDirectory)) {
    throw "ActiveDirectory module missing. Install RSAT-AD-PowerShell."
}

Import-Module ActiveDirectory

if (-not (Test-Path $ShareRoot)) {
    New-Item -ItemType Directory -Path $ShareRoot -Force |
        Out-Null
}

if (Get-SmbShare -Name "IT-Projects" -ErrorAction SilentlyContinue) {
    throw "Existing SMB configuration detected. Review before deployment."
}

# ============================================================
# 3. INSTALL IIS FTP
# ============================================================

Write-Host "`n[2/15] INSTALL IIS FTP" -ForegroundColor Cyan

Install-WindowsFeature `
    Web-Server, `
    Web-Ftp-Server, `
    Web-Ftp-Service, `
    Web-Ftp-Ext, `
    Web-Mgmt-Console `
    -IncludeManagementTools

# ============================================================
# 4. CREATE ACTIVE DIRECTORY GROUPS
# ============================================================

Write-Host "`n[3/15] ACTIVE DIRECTORY GROUPS" -ForegroundColor Cyan

$ADDomain = Get-ADDomain
$ADGroupOU = $ADDomain.UsersContainer

foreach ($Department in $Departments) {

    $Group = "$ADGroupPrefix$($Department.Name)"

    if (-not (Get-ADGroup -Identity $Group -ErrorAction SilentlyContinue)) {

        New-ADGroup `
            -Name $Group `
            -SamAccountName $Group `
            -GroupCategory Security `
            -GroupScope Global `
            -Path $ADGroupOU `
            -Description "Department file access"
    }
}

# ============================================================
# 5. CREATE LOCAL FTP USERS AND GROUPS
# ============================================================

Write-Host "`n[4/15] LOCAL FTP USERS" -ForegroundColor Cyan

foreach ($Department in $Departments) {

    $Group = "$LocalGroupPrefix$($Department.Name)"

    if (-not (Get-LocalGroup -Name $Group -ErrorAction SilentlyContinue)) {
        New-LocalGroup -Name $Group
    }

    foreach ($User in $Department.Users) {

        if (-not (Get-LocalUser -Name $User -ErrorAction SilentlyContinue)) {

            $Password = Read-Host "Password for $User" -AsSecureString

            New-LocalUser `
                -Name $User `
                -Password $Password `
                -Description "FTP account $($Department.Name)"
        }

        Add-LocalGroupMember `
            -Group $Group `
            -Member $User `
            -ErrorAction SilentlyContinue
    }
}

# ============================================================
# 6. CREATE DIRECTORY STRUCTURE
# ============================================================

Write-Host "`n[5/15] CREATE D:\shares" -ForegroundColor Cyan

foreach ($Department in $Departments) {

    $Base = "$ShareRoot\$($Department.Name)"

    New-Item -ItemType Directory -Path "$Base\projects" -Force |
        Out-Null

    New-Item -ItemType Directory -Path "$Base\software" -Force |
        Out-Null

    foreach ($Year in $Years) {
        New-Item -ItemType Directory `
            -Path "$Base\projects\$Year" -Force |
            Out-Null
    }
}

# ============================================================
# 7. BACKUP NTFS PERMISSIONS
# ============================================================

Write-Host "`n[6/15] BACKUP ACLS" -ForegroundColor Cyan

New-Item -ItemType Directory -Path $BackupRoot -Force |
    Out-Null

if ($ResetDepartmentACLs) {

    & icacls.exe $ShareRoot /save "$BackupRoot\shares-acl.txt" /T /C

    if ($LASTEXITCODE -ne 0) {
        throw "ACL backup failed."
    }
}

# ============================================================
# 8. CONFIGURE NTFS PERMISSIONS
# ============================================================

Write-Host "`n[7/15] NTFS PERMISSIONS" -ForegroundColor Cyan

& icacls.exe $ShareRoot /inheritance:r

& icacls.exe $ShareRoot /grant:r `
    "SYSTEM:(OI)(CI)F" `
    "BUILTIN\Administrators:(OI)(CI)F"

foreach ($Department in $Departments) {

    $Name = $Department.Name
    $Path = "$ShareRoot\$Name"

    $LocalGroup = "$ServerName\$LocalGroupPrefix$Name"
    $ADGroup = "$Domain\$ADGroupPrefix$Name"

    if ($ResetDepartmentACLs) {
        & icacls.exe $Path /reset /T /C

        if ($LASTEXITCODE -ne 0) {
            throw "ACL reset failed: $Path"
        }
    }

    & icacls.exe $Path /inheritance:r

    & icacls.exe $Path /grant:r `
        "SYSTEM:(OI)(CI)F" `
        "BUILTIN\Administrators:(OI)(CI)F" `
        "${LocalGroup}:(OI)(CI)M" `
        "${ADGroup}:(OI)(CI)M"

    if ($LASTEXITCODE -ne 0) {
        throw "NTFS configuration failed: $Path"
    }
}

# ============================================================
# 9. CREATE FTP HOME DIRECTORIES
# ============================================================

Write-Host "`n[8/15] FTP HOME DIRECTORIES" -ForegroundColor Cyan

$LocalUserRoot = "$FtpRoot\LocalUser"

New-Item -ItemType Directory -Path $LocalUserRoot -Force |
    Out-Null

foreach ($Department in $Departments) {

    $Name = $Department.Name
    $Group = "$ServerName\$LocalGroupPrefix$Name"

    foreach ($User in $Department.Users) {

        $Home = "$LocalUserRoot\$User"

        New-Item -ItemType Directory -Path $Home -Force |
            Out-Null

        & icacls.exe $Home /inheritance:r

        & icacls.exe $Home /grant:r `
            "SYSTEM:(OI)(CI)F" `
            "BUILTIN\Administrators:(OI)(CI)F" `
            "${Group}:(OI)(CI)RX"
    }
}

& icacls.exe $FtpRoot /inheritance:r
& icacls.exe $FtpRoot /grant:r `
    "SYSTEM:(OI)(CI)F" `
    "BUILTIN\Administrators:(OI)(CI)F" `
    "Authenticated Users:(X)"

& icacls.exe $LocalUserRoot /inheritance:r
& icacls.exe $LocalUserRoot /grant:r `
    "SYSTEM:(OI)(CI)F" `
    "BUILTIN\Administrators:(OI)(CI)F" `
    "Authenticated Users:(X)"

# ============================================================
# 10. CREATE FTPS CERTIFICATE
# ============================================================

Write-Host "`n[9/15] FTPS CERTIFICATE" -ForegroundColor Cyan

$Cert = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object {
        $_.DnsNameList.Unicode -contains $FtpDNSName `
        -and $_.HasPrivateKey `
        -and $_.NotAfter -gt (Get-Date)
    } |
    Select-Object -First 1

if (-not $Cert -and $CreateSelfSignedCertificate) {

    $Cert = New-SelfSignedCertificate `
        -DnsName $FtpDNSName `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -FriendlyName "Department FTP FTPS"
}

if (-not $Cert) {
    throw "FTPS certificate missing."
}

$Thumbprint = $Cert.Thumbprint

Export-Certificate `
    -Cert $Cert `
    -FilePath "$FtpRoot\FTP-Server-Certificate.cer" `
    -Force | Out-Null

# ============================================================
# 11. CREATE IIS FTP SITE
# ============================================================

Write-Host "`n[10/15] IIS FTP CONFIGURATION" -ForegroundColor Cyan

if (Get-Website -Name $FtpSite -ErrorAction SilentlyContinue) {
    throw "IIS site already exists: $FtpSite"
}

& $AppCmd add site `
    "/name:$FtpSite" `
    "/bindings:ftp/$($ServerIP):$FtpPort:" `
    "/physicalPath:$FtpRoot"

& $AppCmd set config $FtpSite `
    -section:system.ftpServer/security/authentication/basicAuthentication `
    /enabled:true /commit:apphost

& $AppCmd set config $FtpSite `
    -section:system.ftpServer/security/authentication/anonymousAuthentication `
    /enabled:false /commit:apphost

& $AppCmd set config `
    -section:system.applicationHost/sites `
    "/[name='$FtpSite'].ftpServer.userIsolation.mode:IsolateAllDirectories" `
    /commit:apphost

& $AppCmd set config `
    -section:system.applicationHost/sites `
    "/[name='$FtpSite'].ftpServer.security.ssl.serverCertHash:$Thumbprint" `
    /commit:apphost

& $AppCmd set config `
    -section:system.applicationHost/sites `
    "/[name='$FtpSite'].ftpServer.security.ssl.serverCertStoreName:MY" `
    /commit:apphost

& $AppCmd set config `
    -section:system.applicationHost/sites `
    "/[name='$FtpSite'].ftpServer.security.ssl.controlChannelPolicy:SslRequire" `
    /commit:apphost

& $AppCmd set config `
    -section:system.applicationHost/sites `
    "/[name='$FtpSite'].ftpServer.security.ssl.dataChannelPolicy:SslRequire" `
    /commit:apphost

# ============================================================
# 12. FTP AUTHORIZATION AND VIRTUAL DIRECTORIES
# ============================================================

Write-Host "`n[11/15] FTP AUTHORIZATION" -ForegroundColor Cyan

foreach ($Department in $Departments) {

    $Name = $Department.Name
    $Group = "$ServerName\$LocalGroupPrefix$Name"

    & $AppCmd set config $FtpSite `
        -section:system.ftpServer/security/authorization `
        "/+[accessType='Allow',roles='$Group',permissions='Read, Write']" `
        /commit:apphost

    foreach ($User in $Department.Users) {

        & $AppCmd add vdir `
            "/app.name:$FtpSite/" `
            "/path:/LocalUser/$User/projects" `
            "/physicalPath:$ShareRoot\$Name\projects"

        if ($LASTEXITCODE -ne 0) {
            throw "Projects vdir failed for $User"
        }

        & $AppCmd add vdir `
            "/app.name:$FtpSite/" `
            "/path:/LocalUser/$User/software" `
            "/physicalPath:$ShareRoot\$Name\software"

        if ($LASTEXITCODE -ne 0) {
            throw "Software vdir failed for $User"
        }
    }
}

# ============================================================
# 13. PASSIVE PORTS
# ============================================================

Write-Host "`n[12/15] PASSIVE FTP PORTS" -ForegroundColor Cyan

& $AppCmd set config `
    -section:system.ftpServer/firewallSupport `
    "/lowDataChannelPort:$PassiveLow" `
    "/highDataChannelPort:$PassiveHigh" `
    /commit:apphost

# ============================================================
# 14. CREATE SMB SHARES
# ============================================================

Write-Host "`n[13/15] SMB SHARES" -ForegroundColor Cyan

foreach ($Department in $Departments) {

    $Name = $Department.Name
    $ADGroup = "$Domain\$ADGroupPrefix$Name"

    foreach ($Type in @("projects", "software")) {

        $ShareName = "$Name-$((Get-Culture).TextInfo.ToTitleCase($Type))"
        $Path = "$ShareRoot\$Name\$Type"

        New-SmbShare `
            -Name $ShareName `
            -Path $Path `
            -FullAccess "BUILTIN\Administrators" `
            -ChangeAccess $ADGroup `
            -FolderEnumerationMode AccessBased
    }
}

# ============================================================
# 15. FIREWALL AND NETLOGON
# ============================================================

Write-Host "`n[14/15] FIREWALL" -ForegroundColor Cyan

New-NetFirewallRule `
    -DisplayName "Department FTP Control" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $FtpPort `
    -RemoteAddress LocalSubnet `
    -Action Allow

New-NetFirewallRule `
    -DisplayName "Department FTP Passive" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort "$PassiveLow-$PassiveHigh" `
    -RemoteAddress LocalSubnet `
    -Action Allow

New-NetFirewallRule `
    -DisplayName "Department SMB" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 445 `
    -RemoteAddress LocalSubnet `
    -Action Allow

Write-Host "`n[15/15] NETLOGON SCRIPT" -ForegroundColor Cyan

$NetlogonPath = "\\$Domain\NETLOGON"

if (-not (Test-Path $NetlogonPath)) {
    throw "NETLOGON unavailable."
}

$Batch = @"
@echo off
setlocal

net use P: /delete /y >nul 2>&1
net use S: /delete /y >nul 2>&1

"@

foreach ($Department in $Departments) {

    $Name = $Department.Name
    $Group = "$ADGroupPrefix$Name"

    $Batch += @"

whoami /groups | findstr /i /c:"$Group" >nul
if not errorlevel 1 (
    net use P: "\\$ServerName\$Name-Projects" /persistent:no
    net use S: "\\$ServerName\$Name-Software" /persistent:no
    goto END
)

"@
}

$Batch += @"

:END
endlocal
exit /b
"@

Set-Content `
    -Path "$NetlogonPath\Map-DepartmentDrives.bat" `
    -Value $Batch `
    -Encoding ASCII

# ============================================================
# START SERVICES
# ============================================================

Set-Service FTPSVC -StartupType Automatic
Start-Service FTPSVC
Start-Service W3SVC

# ============================================================
# FINAL SUMMARY
# ============================================================

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "DEPARTMENT FTP DEPLOYMENT FINISHED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "Server: $ServerName"
Write-Host "Domain: $Domain"
Write-Host "FTP Site: $FtpSite"
Write-Host "FTPS Host: $FtpDNSName"
Write-Host "FTPS Port: $FtpPort"
Write-Host "Passive Ports: $PassiveLow-$PassiveHigh"
Write-Host "Data: $ShareRoot"
Write-Host "Certificate: $Thumbprint"
Write-Host "NETLOGON: $NetlogonPath\Map-DepartmentDrives.bat"

Write-Host "`nIMPORTANT: Verify all FTP and SMB permissions before production use." -ForegroundColor Yellow
