#requires -Version 5.1
#requires -RunAsAdministrator
<#
 Complete IIS FTP deployment for a domain-joined Windows Server.
 Creates/reuses AD FTP group, provisions isolated user folders,
 configures explicit FTPS, firewall and passive ports.
 Review before running on production servers.
#>
$ErrorActionPreference = 'Stop'

# ===================== CONFIGURATION =====================
$FtpSiteName = 'AD-FTP'
$FtpRoot = 'D:\FTP'
$FallbackFtpRoot = 'C:\AD-FTP'
$AllowFallbackFtpRoot = $true
$FtpPort = 21
$PassivePortStart = 50000
$PassivePortEnd = 50100
$FtpGroupName = 'FTP-Users'
$FtpDirectoryName = 'LocalUser'
$EnableFTPS = $true
$RequireSSL = $true
$CertificateThumbprint = ''
$CreateSelfSignedCertificateIfMissing = $true
$FtpDnsName = 'lifs01.kks.local'
# =========================================================

function Assert-DirectoryWritable {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Directory not found: $Path"
    }
    $Probe = Join-Path $Path ('.ftp-write-test-' + [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($Probe, 'test')
    }
    catch {
        throw "No write access to '$Path' for $([Security.Principal.WindowsIdentity]::GetCurrent().Name). Review NTFS ACLs and any explicit Deny rules. Original error: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path -LiteralPath $Probe) {
            Remove-Item -LiteralPath $Probe -Force -ErrorAction SilentlyContinue
        }
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw "Path exists but is not a directory: $Path"
        }
        Assert-DirectoryWritable -Path $Path
        return
    }
    $Parent = Split-Path -Path $Path -Parent
    if (-not $Parent) { throw "Cannot determine parent directory for $Path" }
    if (-not (Test-Path -LiteralPath $Parent -PathType Container)) {
        Ensure-Directory -Path $Parent
    }
    Assert-DirectoryWritable -Path $Parent
    try {
        New-Item -Path $Path -ItemType Directory -ErrorAction Stop | Out-Null
    }
    catch {
        throw "Cannot create directory '$Path'. Check permissions on '$Parent'. Original error: $($_.Exception.Message)"
    }
    Assert-DirectoryWritable -Path $Path
}

function Add-FileAccessRule {
    param(
        [string]$Path, [string]$Identity, [string]$Rights,
        [string]$Inheritance = 'None'
    )
    $Acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity, $Rights, $Inheritance, 'None', 'Allow'
    )
    $Acl.SetAccessRule($Rule)
    Set-Acl -LiteralPath $Path -AclObject $Acl -ErrorAction Stop
}

$LogDirectory = Join-Path $env:ProgramData 'AD-Deployment'
New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
$TranscriptStarted = $false
try {
    Start-Transcript -Path (Join-Path $LogDirectory 'FTP-Deployment.log') -Append -ErrorAction Stop | Out-Null
    $TranscriptStarted = $true

    Write-Host "`n=== PRE-FLIGHT ===" -ForegroundColor Cyan
    if ($PassivePortStart -lt 1024 -or $PassivePortEnd -gt 65535 -or $PassivePortStart -gt $PassivePortEnd) {
        throw 'Invalid passive port range.'
    }
    if ($FtpPort -lt 1 -or $FtpPort -gt 65535) { throw 'Invalid FTP port.' }
    if ($FtpRoot -notmatch '^[A-Za-z]:\\') { throw 'FtpRoot must be an absolute local drive path.' }
    if ($FtpRoot.TrimEnd('\') -match '^[A-Za-z]:$') { throw 'FtpRoot must be a subdirectory, not a drive root.' }

    Write-Host "`n=== SYSTEM VALIDATION ===" -ForegroundColor Cyan
    $Computer = Get-CimInstance Win32_ComputerSystem
    if (-not $Computer.PartOfDomain) { throw 'Server must be joined to an AD domain.' }
    $DomainName = $Computer.Domain
    Write-Host "Computer: $($Computer.Name); Domain: $DomainName"

    Write-Host "`n=== FTP ROOT ACCESS CHECK ===" -ForegroundColor Cyan
    $RequestedFtpRoot = $FtpRoot
    $RootCandidates = @($RequestedFtpRoot)
    if ($AllowFallbackFtpRoot -and $FallbackFtpRoot -ne $RequestedFtpRoot) {
        $RootCandidates += $FallbackFtpRoot
    }
    $RootReady = $false
    foreach ($CandidateRoot in $RootCandidates) {
        try {
            $DriveName = $CandidateRoot.Substring(0, 1)
            if (-not (Test-Path -LiteralPath ($DriveName + ':\') -PathType Container)) {
                throw "Drive $($DriveName): is not available."
            }
            Ensure-Directory -Path $CandidateRoot
            $FtpRoot = $CandidateRoot
            $RootReady = $true
            break
        }
        catch {
            Write-Warning "Cannot use '$CandidateRoot': $($_.Exception.Message)"
        }
    }
    if (-not $RootReady) {
        throw "Neither requested FTP root nor fallback is writable. Check NTFS permissions; no ownership or ACL reset was attempted."
    }
    if ($FtpRoot -ne $RequestedFtpRoot) {
        Write-Warning "FTP root changed from '$RequestedFtpRoot' to '$FtpRoot'. Review this change before production use."
    }
    Write-Host "Selected FTP root: $FtpRoot" -ForegroundColor Green

    Write-Host "`n=== FTPS CERTIFICATE ===" -ForegroundColor Cyan
    if ($EnableFTPS) {
        $CertificateThumbprint = ($CertificateThumbprint -replace '\s', '').ToUpperInvariant()
        if ($CertificateThumbprint -and $CertificateThumbprint -notmatch '^[0-9A-F]{40}$') {
            throw 'Invalid certificate thumbprint (expected 40 hexadecimal characters).'
        }
        $Certificate = $null
        if ($CertificateThumbprint) {
            $Certificate = Get-Item -LiteralPath "Cert:\LocalMachine\My\$CertificateThumbprint" -ErrorAction Stop
        }
        else {
            $Certificate = Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object {
                $_.HasPrivateKey -and $_.NotBefore -le (Get-Date) -and
                $_.NotAfter -gt (Get-Date).AddDays(30) -and
                ($_.DnsNameList.Unicode -contains $FtpDnsName) -and
                (@($_.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId }) -contains '1.3.6.1.5.5.7.3.1')
            } | Sort-Object NotAfter -Descending | Select-Object -First 1
            if (-not $Certificate) {
                if (-not $CreateSelfSignedCertificateIfMissing) { throw "No suitable certificate for $FtpDnsName found." }
                Write-Warning "Creating a self-signed certificate for $FtpDnsName; clients must trust it explicitly."
                $Certificate = New-SelfSignedCertificate -DnsName $FtpDnsName -CertStoreLocation 'Cert:\LocalMachine\My' -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -Type SSLServerAuthentication -NotAfter (Get-Date).AddYears(2) -ErrorAction Stop
            }
            $CertificateThumbprint = $Certificate.Thumbprint
        }
        if (-not $Certificate.HasPrivateKey -or $Certificate.NotBefore -gt (Get-Date) -or $Certificate.NotAfter -le (Get-Date)) {
            throw 'Certificate is expired, not yet valid, or missing its private key.'
        }
        $Eku = @($Certificate.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId })
        if ($Eku.Count -gt 0 -and $Eku -notcontains '1.3.6.1.5.5.7.3.1') { throw 'Certificate is not valid for Server Authentication.' }
        Write-Host "Certificate: $($Certificate.Subject); Thumbprint: $CertificateThumbprint"
    }

    Write-Host "`n=== ACTIVE DIRECTORY MODULE ===" -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable ActiveDirectory)) {
        $Result = Install-WindowsFeature RSAT-AD-PowerShell -ErrorAction Stop
        if (-not $Result.Success -or $Result.RestartNeeded -eq 'Yes') { throw 'AD module installation failed or restart required.' }
    }
    Import-Module ActiveDirectory -ErrorAction Stop

    Write-Host "`n=== DOMAIN CONTROLLER DISCOVERY ===" -ForegroundColor Cyan
    $DomainController = $null
    try {
        $DC = Get-ADDomainController -Discover -DomainName $DomainName -Service ADWS -ErrorAction Stop
        if ($DC.HostName) { $DomainController = [string]$DC.HostName }
    }
    catch { Write-Warning "ADWS discovery failed: $($_.Exception.Message)" }
    if (-not $DomainController) {
        $SrvRecords = @(Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV -ErrorAction Stop | Sort-Object Priority)
        foreach ($Srv in $SrvRecords) {
            $Candidate = ([string]$Srv.NameTarget).TrimEnd('.')
            try {
                Get-ADDomain -Identity $DomainName -Server $Candidate -ErrorAction Stop | Out-Null
                $DomainController = $Candidate
                break
            }
            catch { Write-Warning "DC $Candidate does not answer ADWS: $($_.Exception.Message)" }
        }
    }
    if (-not $DomainController) { throw "Cannot discover a usable AD Domain Controller for $DomainName." }
    $Domain = Get-ADDomain -Identity $DomainName -Server $DomainController -ErrorAction Stop
    $DomainDN = $Domain.DistinguishedName
    $DomainNetBIOS = $Domain.NetBIOSName
    if (-not (Test-ComputerSecureChannel -Server $DomainController -ErrorAction Stop)) { throw 'Domain secure channel is unhealthy.' }
    Write-Host "Domain Controller: $DomainController" -ForegroundColor Green

    Write-Host "`n=== FTP AD GROUP ===" -ForegroundColor Cyan
    $EscapedGroupName = $FtpGroupName.Replace('\','\5c').Replace('*','\2a').Replace('(','\28').Replace(')','\29')
    $Matches = @(Get-ADGroup -LDAPFilter "(sAMAccountName=$EscapedGroupName)" -SearchBase $DomainDN -Server $DomainController -ErrorAction Stop)
    if ($Matches.Count -gt 1) { throw "Ambiguous AD group: $FtpGroupName" }
    if ($Matches.Count -eq 1) { $FtpGroup = $Matches[0] }
    else {
        $FtpGroup = New-ADGroup -Name $FtpGroupName -SamAccountName $FtpGroupName -GroupCategory Security -GroupScope Global -Path "CN=Users,$DomainDN" -Description 'FTP authorized users' -Server $DomainController -PassThru -ErrorAction Stop
    }
    $GroupIdentity = "$DomainNetBIOS\$FtpGroupName"
    Write-Host "FTP group: $GroupIdentity"

    Write-Host "`n=== INSTALL IIS FTP ===" -ForegroundColor Cyan
    $FeatureResult = Install-WindowsFeature -Name Web-Server,Web-FTP-Server,Web-FTP-Service,Web-FTP-Ext -IncludeManagementTools -ErrorAction Stop
    if (-not $FeatureResult.Success -or $FeatureResult.RestartNeeded -eq 'Yes') { throw 'IIS FTP installation failed or restart required.' }
    Import-Module WebAdministration -ErrorAction Stop

    Write-Host "`n=== FTP DIRECTORY STRUCTURE ===" -ForegroundColor Cyan
    $LocalUserRoot = Join-Path $FtpRoot $FtpDirectoryName
    $DomainUserRoot = Join-Path $LocalUserRoot $DomainNetBIOS
    foreach ($Folder in @($LocalUserRoot, $DomainUserRoot)) { Ensure-Directory -Path $Folder }

    Write-Host "`n=== NTFS PERMISSIONS ===" -ForegroundColor Cyan
    foreach ($Folder in @($FtpRoot, $LocalUserRoot, $DomainUserRoot)) {
        Add-FileAccessRule -Path $Folder -Identity $GroupIdentity -Rights 'ReadAndExecute'
    }

    Write-Host "`n=== FTP USER DIRECTORIES ===" -ForegroundColor Cyan
    $Members = @(Get-ADGroupMember -Identity $FtpGroup.DistinguishedName -Recursive -Server $DomainController -ErrorAction Stop | Where-Object { $_.objectClass -eq 'user' })
    $CreatedCount = 0
    foreach ($Member in $Members) {
        $User = Get-ADUser -Identity $Member.DistinguishedName -Server $DomainController -ErrorAction Stop
        $Sam = $User.SamAccountName
        if ([string]::IsNullOrWhiteSpace($Sam)) { continue }
        $UserPath = Join-Path $DomainUserRoot $Sam
        Ensure-Directory -Path $UserPath
        $Acl = Get-Acl -LiteralPath $UserPath
        # Existing folders are not automatically stripped of permissions.
        # Review existing ACLs before using the site with sensitive data.
        if ($Acl.AreAccessRulesProtected -eq $false) {
            $Acl.SetAccessRuleProtection($true, $false)
        }
        foreach ($Account in @('BUILTIN\Administrators', 'NT AUTHORITY\SYSTEM')) {
            $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule($Account,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
            $Acl.SetAccessRule($Rule)
        }
        $UserRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$DomainNetBIOS\$Sam",'Modify','ContainerInherit,ObjectInherit','None','Allow')
        $Acl.SetAccessRule($UserRule)
        Set-Acl -LiteralPath $UserPath -AclObject $Acl -ErrorAction Stop
        $CreatedCount++
    }
    Write-Host "Provisioned home directories: $CreatedCount"
    if ($CreatedCount -eq 0) { Write-Warning 'Add users to FTP-Users and rerun to provision home directories.' }

    Write-Host "`n=== IIS FTP SITE ===" -ForegroundColor Cyan
    $Site = Get-Website -Name $FtpSiteName -ErrorAction SilentlyContinue
    if (-not $Site) {
        New-WebFtpSite -Name $FtpSiteName -Port $FtpPort -PhysicalPath $FtpRoot -Force -ErrorAction Stop | Out-Null
    }
    elseif ($Site.PhysicalPath -ne $FtpRoot) {
        throw "Existing site $FtpSiteName has physical path $($Site.PhysicalPath), expected $FtpRoot."
    }
    $ConfigPath = 'MACHINE/WEBROOT/APPHOST'
    $SiteLocation = $FtpSiteName

    Write-Host "`n=== FTP AUTHENTICATION AND AUTHORIZATION ===" -ForegroundColor Cyan
    Set-WebConfigurationProperty -PSPath $ConfigPath -Location $SiteLocation -Filter 'system.ftpServer/security/authentication/anonymousAuthentication' -Name enabled -Value $false -ErrorAction Stop
    Set-WebConfigurationProperty -PSPath $ConfigPath -Location $SiteLocation -Filter 'system.ftpServer/security/authentication/basicAuthentication' -Name enabled -Value $true -ErrorAction Stop
    Clear-WebConfiguration -PSPath $ConfigPath -Location $SiteLocation -Filter 'system.ftpServer/security/authorization' -ErrorAction Stop
    Add-WebConfiguration -PSPath $ConfigPath -Location $SiteLocation -Filter 'system.ftpServer/security/authorization' -Value @{ accessType='Allow'; roles=$GroupIdentity; permissions='Read, Write' } -ErrorAction Stop

    Write-Host "`n=== FTP USER ISOLATION ===" -ForegroundColor Cyan
    Set-WebConfigurationProperty -PSPath $ConfigPath -Location $SiteLocation -Filter 'system.ftpServer/userIsolation' -Name mode -Value 'IsolateAllDirectories' -ErrorAction Stop

    Write-Host "`n=== PASSIVE FTP PORTS ===" -ForegroundColor Cyan
    Set-WebConfigurationProperty -PSPath $ConfigPath -Filter 'system.ftpServer/firewallSupport' -Name lowDataChannelPort -Value $PassivePortStart -ErrorAction Stop
    Set-WebConfigurationProperty -PSPath $ConfigPath -Filter 'system.ftpServer/firewallSupport' -Name highDataChannelPort -Value $PassivePortEnd -ErrorAction Stop

    Write-Host "`n=== FTPS SETTINGS ===" -ForegroundColor Cyan
    if ($EnableFTPS) {
        $SslPolicy = if ($RequireSSL) { 'SslRequire' } else { 'SslAllow' }
        Set-WebConfigurationProperty -PSPath $ConfigPath -Location $SiteLocation -Filter 'system.ftpServer/security/ssl' -Name serverCertHash -Value $CertificateThumbprint -ErrorAction Stop
    }
    else {
        $SslPolicy = 'SslAllow'
        Write-Warning 'FTPS is disabled. Credentials may be sent unencrypted.'
    }
    Set-WebConfigurationProperty -PSPath $ConfigPath -Location $SiteLocation -Filter 'system.ftpServer/security/ssl' -Name controlChannelPolicy -Value $SslPolicy -ErrorAction Stop
    Set-WebConfigurationProperty -PSPath $ConfigPath -Location $SiteLocation -Filter 'system.ftpServer/security/ssl' -Name dataChannelPolicy -Value $SslPolicy -ErrorAction Stop

    Write-Host "`n=== WINDOWS FIREWALL ===" -ForegroundColor Cyan
    $Rules = @(@{Name='AD-FTP-Control';Ports=[string]$FtpPort},@{Name='AD-FTP-Passive';Ports="$PassivePortStart-$PassivePortEnd"})
    foreach ($Rule in $Rules) {
        $Existing = Get-NetFirewallRule -DisplayName $Rule.Name -ErrorAction SilentlyContinue
        if ($Existing) {
            Set-NetFirewallRule -DisplayName $Rule.Name -Enabled True -Profile Domain -Direction Inbound -Action Allow -ErrorAction Stop | Out-Null
            Set-NetFirewallPortFilter -AssociatedNetFirewallRule $Existing -Protocol TCP -LocalPort $Rule.Ports -ErrorAction Stop | Out-Null
        }
        else {
            New-NetFirewallRule -DisplayName $Rule.Name -Direction Inbound -Protocol TCP -LocalPort $Rule.Ports -Action Allow -Profile Domain -ErrorAction Stop | Out-Null
        }
    }

    Write-Host "`n=== START FTP SERVICE ===" -ForegroundColor Cyan
    Set-Service FTPSVC -StartupType Automatic -ErrorAction Stop
    if ((Get-Service FTPSVC).Status -ne 'Running') { Start-Service FTPSVC -ErrorAction Stop }
    if ((Get-Website -Name $FtpSiteName).State -ne 'Started') { Start-WebSite -Name $FtpSiteName -ErrorAction Stop }
    else { Restart-WebItem -PSPath "IIS:\Sites\$FtpSiteName" -ErrorAction Stop }

    Write-Host "`n=== FINAL VALIDATION ===" -ForegroundColor Cyan
    Get-Website -Name $FtpSiteName | Format-List Name,State,PhysicalPath
    Write-Host "Domain: $DomainName"
    Write-Host "Domain Controller: $DomainController"
    Write-Host "Authorized group: $GroupIdentity"
    Write-Host "FTP root: $FtpRoot"
    Write-Host "User home directory parent: $DomainUserRoot"
    Write-Host "Passive ports: $PassivePortStart-$PassivePortEnd"
    Write-Host "FTPS enabled: $EnableFTPS; SSL policy: $SslPolicy"
    Write-Warning 'Test AD logins, per-user isolation, FTPS trust and passive transfers before production use. Configure external IP/port forwarding if behind NAT.'
    Write-Host 'FTP deployment completed.' -ForegroundColor Green
}
catch {
    Write-Host "`nDEPLOYMENT FAILED: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally {
    if ($TranscriptStarted) { Stop-Transcript | Out-Null }
}
