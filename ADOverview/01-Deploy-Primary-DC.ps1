
#requires -RunAsAdministrator
#requires -Version 5.1

<#
    01-Deploy-Primary-DC.ps1

    Creates:
      - New Active Directory forest
      - Primary Domain Controller
      - DNS Server
      - DHCP Server
      - DHCP pools from configured address ranges

    Run once before promotion and once after reboot.
#>

$ErrorActionPreference = "Stop"

# =========================================================
# ONLY USER-MAINTAINED CONFIGURATION
# =========================================================

$DhcpPools = @(
    @{
        Name       = "Bereich 1"
        StartRange = "192.168.100.1"
        EndRange   = "192.168.100.11"
        SubnetMask = "255.255.255.0"
    },
    @{
        Name       = "Bereich 2"
        StartRange = "192.168.100.20"
        EndRange   = "192.168.100.30"
        SubnetMask = "255.255.255.0"
    }
)

# =========================================================
# HELPERS
# =========================================================

$LogDirectory = "$env:ProgramData\AD-Deployment"
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

Start-Transcript -Path (
    Join-Path $LogDirectory "Primary-DC.log"
) -Append | Out-Null

function Convert-IPToUInt32 {
    param([string]$IP)

    $bytes = [System.Net.IPAddress]::Parse($IP).GetAddressBytes()
    [array]::Reverse($bytes)

    return [BitConverter]::ToUInt32($bytes, 0)
}

function Convert-UInt32ToIP {
    param([uint32]$Value)

    $bytes = [BitConverter]::GetBytes($Value)
    [array]::Reverse($bytes)

    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Get-NetworkID {
    param(
        [string]$IP,
        [string]$Mask
    )

    $ipNumber = Convert-IPToUInt32 $IP
    $maskNumber = Convert-IPToUInt32 $Mask

    return Convert-UInt32ToIP ($ipNumber -band $maskNumber)
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity

    if (-not $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )) {
        throw "Run this script as Administrator."
    }
}

function Get-PrimaryIPv4 {
    $routes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
        Sort-Object RouteMetric

    foreach ($route in $routes) {
        $address = Get-NetIPAddress `
            -InterfaceIndex $route.InterfaceIndex `
            -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notlike "169.254.*"
            } |
            Select-Object -First 1

        if ($address) {
            return $address
        }
    }

    throw "No usable IPv4 address/default route found."
}

# =========================================================
# INITIAL VALIDATION
# =========================================================

Assert-Administrator

$Computer = Get-CimInstance Win32_ComputerSystem
$ServerIP = Get-PrimaryIPv4
$Gateway = Get-NetRoute `
    -InterfaceIndex $ServerIP.InterfaceIndex `
    -DestinationPrefix "0.0.0.0/0" |
    Sort-Object RouteMetric |
    Select-Object -First 1

Write-Host "`nServer: $env:COMPUTERNAME"
Write-Host "IPv4: $($ServerIP.IPAddress)"
Write-Host "Gateway: $($Gateway.NextHop)"

if ($ServerIP.PrefixOrigin -eq "Dhcp") {
    throw "The server uses DHCP. Configure a static IP before deployment."
}

# Validate configured DHCP pools
foreach ($pool in $DhcpPools) {
    $start = Convert-IPToUInt32 $pool.StartRange
    $end = Convert-IPToUInt32 $pool.EndRange
    $mask = Convert-IPToUInt32 $pool.SubnetMask

    if ($start -gt $end) {
        throw "Invalid range: $($pool.Name)"
    }

    if ((($start -band $mask) -ne ($end -band $mask))) {
        throw "DHCP pool $($pool.Name) crosses subnet boundaries."
    }
}

# =========================================================
# STAGE 1: CREATE NEW FOREST
# =========================================================

if ($Computer.DomainRole -lt 4) {

    if ($Computer.PartOfDomain) {
        throw "This server is already domain-joined. Use a separate domain deployment procedure."
    }

    Write-Host "`nInstalling Windows Server roles..." -ForegroundColor Cyan

    Install-WindowsFeature `
        AD-Domain-Services, DHCP `
        -IncludeManagementTools

    $DomainName = Read-Host "Enter your NEW AD domain (example: kks.local)"

    if ($DomainName -notmatch '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
        throw "Invalid DNS domain name."
    }

    $ExistingDomain = Get-ADDomain -ErrorAction SilentlyContinue

    if ($ExistingDomain) {
        throw "An AD domain already exists. Refusing to create another forest."
    }

    $DSRMPassword = Read-Host `
        "Enter Directory Services Restore Mode password" `
        -AsSecureString

    Write-Host "`nCreating forest: $DomainName" -ForegroundColor Yellow

    Install-ADDSForest `
        -DomainName $DomainName `
        -InstallDNS `
        -SafeModeAdministratorPassword $DSRMPassword `
        -NoRebootOnCompletion `
        -Force

    Write-Host "Forest created. Restarting server..."

    Stop-Transcript | Out-Null
    Restart-Computer -Force
    exit
}

# =========================================================
# STAGE 2: CONFIGURE DHCP AFTER FOREST PROMOTION
# =========================================================

Import-Module ActiveDirectory
Import-Module DhcpServer
Import-Module DnsServer

$DomainName = (Get-ADDomain).DNSRoot

Write-Host "`nExisting domain detected: $DomainName"

Install-WindowsFeature DHCP -IncludeManagementTools

# Confirm DHCP authorization
$Authorized = Get-DhcpServerInDC |
    Where-Object {
        $_.IPAddress -eq $ServerIP.IPAddress
    }

if (-not $Authorized) {
    Add-DhcpServerInDC `
        -DnsName "$env:COMPUTERNAME.$DomainName" `
        -IPAddress $ServerIP.IPAddress
}

Set-Service DHCPServer -StartupType Automatic
Start-Service DHCPServer

# =========================================================
# GROUP POOLS BY SUBNET
# =========================================================

$Groups = $DhcpPools | Group-Object {
    Get-NetworkID $_.StartRange $_.SubnetMask
}

foreach ($group in $Groups) {

    $Pools = @($group.Group)
    $NetworkID = $group.Name
    $Mask = $Pools[0].SubnetMask

    foreach ($pool in $Pools) {
        if ($pool.SubnetMask -ne $Mask) {
            throw "Different subnet masks found in subnet $NetworkID."
        }
    }

    $SortedPools = @(
        $Pools | Sort-Object {
            Convert-IPToUInt32 $_.StartRange
        }
    )

    # Check for overlapping desired pools
    for ($i = 1; $i -lt $SortedPools.Count; $i++) {
        $previousEnd = Convert-IPToUInt32 $SortedPools[$i-1].EndRange
        $currentStart = Convert-IPToUInt32 $SortedPools[$i].StartRange

        if ($currentStart -le $previousEnd) {
            throw "Overlapping DHCP pools detected in $NetworkID."
        }
    }

    $Start = $SortedPools[0].StartRange
    $End = $SortedPools[-1].EndRange

    Write-Host "`nConfiguring subnet $NetworkID"

    $Scope = Get-DhcpServerv4Scope `
        -ScopeId $NetworkID `
        -ErrorAction SilentlyContinue

    if (-not $Scope) {

        Add-DhcpServerv4Scope `
            -Name ($Pools.Name -join " + ") `
            -ScopeId $NetworkID `
            -StartRange $Start `
            -EndRange $End `
            -SubnetMask $Mask `
            -State InActive

    }
    else {

        $scopeStart = Convert-IPToUInt32 $Scope.StartRange
        $scopeEnd = Convert-IPToUInt32 $Scope.EndRange

        if (
            (Convert-IPToUInt32 $Start) -lt $scopeStart -or
            (Convert-IPToUInt32 $End) -gt $scopeEnd
        ) {
            throw "Existing scope $NetworkID does not cover the requested pools. Manual migration required."
        }
    }

    # Create exclusions between the configured pools
    for ($i = 0; $i -lt ($SortedPools.Count - 1); $i++) {

        $gapStart = (Convert-IPToUInt32 $SortedPools[$i].EndRange) + 1
        $gapEnd = (Convert-IPToUInt32 $SortedPools[$i+1].StartRange) - 1

        if ($gapStart -le $gapEnd) {

            $ExclusionStart = Convert-UInt32ToIP $gapStart
            $ExclusionEnd = Convert-UInt32ToIP $gapEnd

            $ExistingExclusions = @(
                Get-DhcpServerv4ExclusionRange `
                    -ScopeId $NetworkID
            )

            $AlreadyCovered = $ExistingExclusions | Where-Object {
                (Convert-IPToUInt32 $_.StartRange) -le $gapStart -and
                (Convert-IPToUInt32 $_.EndRange) -ge $gapEnd
            }

            if (-not $AlreadyCovered) {
                Add-DhcpServerv4ExclusionRange `
                    -ScopeId $NetworkID `
                    -StartRange $ExclusionStart `
                    -EndRange $ExclusionEnd
            }
        }
    }

    # Reserve server and gateway IPs if inside the DHCP range
    $ReservedIPs = @($ServerIP.IPAddress)

    if ($Gateway) {
        $ReservedIPs += $Gateway.NextHop
    }

    foreach ($ReservedIP in ($ReservedIPs | Select-Object -Unique)) {

        $number = Convert-IPToUInt32 $ReservedIP

        if (
            $number -ge (Convert-IPToUInt32 $Start) -and
            $number -le (Convert-IPToUInt32 $End)
        ) {

            $ExistingExclusions = @(
                Get-DhcpServerv4ExclusionRange -ScopeId $NetworkID
            )

            $Covered = $ExistingExclusions | Where-Object {
                (Convert-IPToUInt32 $_.StartRange) -le $number -and
                (Convert-IPToUInt32 $_.EndRange) -ge $number
            }

            if (-not $Covered) {
                Add-DhcpServerv4ExclusionRange `
                    -ScopeId $NetworkID `
                    -StartRange $ReservedIP `
                    -EndRange $ReservedIP
            }
        }
    }

    # DNS and gateway options
    $OptionArguments = @{
        ScopeId = $NetworkID
        DnsServer = $ServerIP.IPAddress
        DnsDomain = $DomainName
    }

    if ($Gateway -and
        (Get-NetworkID $Gateway.NextHop $Mask) -eq $NetworkID) {
        $OptionArguments.Router = $Gateway.NextHop
    }

    Set-DhcpServerv4OptionValue @OptionArguments

    # Activate only after successful configuration
    Set-DhcpServerv4Scope `
        -ScopeId $NetworkID `
        -State Active
}

# =========================================================
# FINAL DIAGNOSTICS
# =========================================================

Write-Host "`nDHCP SCOPES:" -ForegroundColor Cyan

Get-DhcpServerv4Scope |
    Format-Table ScopeId, Name, StartRange, EndRange, State

Write-Host "`nDNS ZONES:" -ForegroundColor Cyan

Get-DnsServerZone |
    Format-Table ZoneName, ZoneType, IsDsIntegrated

Write-Host "`nAD DOMAIN:" -ForegroundColor Cyan

Get-ADDomain | Select-Object DNSRoot, DomainMode

Write-Host "`nDeployment finished."
Write-Host "Log: $LogDirectory"

Stop-Transcript | Out-Null
