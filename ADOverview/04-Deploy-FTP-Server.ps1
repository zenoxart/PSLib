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