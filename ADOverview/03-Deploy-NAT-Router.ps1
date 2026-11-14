
#requires -RunAsAdministrator
#requires -Version 5.1

<#
    03-Deploy-NAT-Router.ps1

    Windows Server NAT router for Hyper-V.

    WAN: Automatically detected by default route.
    LAN: Automatically detected as the other active adapter.

    Internal network:
        Router: 192.168.100.254
        Network: 192.168.100.0/24

    Uses Windows WinNAT.
    Does not install or configure RRAS.
#>

$ErrorActionPreference = "Stop"

# =========================================================
# CONFIGURATION
# =========================================================

$InternalIP = "192.168.100.254"
$InternalPrefix = 24
$InternalNetwork = "192.168.100.0/24"
$NatName = "ADLab-NAT"

$LogDirectory = "$env:ProgramData\AD-Deployment"

New-Item -Path $LogDirectory `
    -ItemType Directory -Force | Out-Null

Start-Transcript `
    -Path "$LogDirectory\NAT-Router.log" `
    -Append | Out-Null

try {

    # =====================================================
    # ADMINISTRATOR CHECK
    # =====================================================

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

    if (-not $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )) {
        throw "Run this script as Administrator."
    }

    Write-Host "`n=== NAT ROUTER DEPLOYMENT ===" `
        -ForegroundColor Cyan

    # =====================================================
    # CHECK WINDOWS NAT / RRAS COMPATIBILITY
    # =====================================================

    $RemoteAccess = Get-Service RemoteAccess `
        -ErrorAction SilentlyContinue

    if ($RemoteAccess -and $RemoteAccess.Status -eq "Running") {
        throw "RRAS is running. WinNAT and RRAS must not be configured together."
    }

    # =====================================================
    # DETECT NETWORK ADAPTERS
    # =====================================================

    $Adapters = @(
        Get-NetAdapter |
        Where-Object {
            $_.Status -eq "Up" -and
            $_.HardwareInterface -eq $true
        }
    )

    if ($Adapters.Count -ne 2) {
        throw "Expected exactly two active physical/virtual network adapters. Found $($Adapters.Count). Check adapter configuration."
    }

    # WAN is the adapter with the default route
    $DefaultRoutes = @(
        Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
        Sort-Object RouteMetric
    )

    if (-not $DefaultRoutes) {
        throw "No default route found. Configure WAN connectivity first."
    }

    $WanIndex = $DefaultRoutes[0].InterfaceIndex

    $WAN = $Adapters |
        Where-Object ifIndex -eq $WanIndex

    $LAN = $Adapters |
        Where-Object ifIndex -ne $WanIndex

    if (-not $WAN -or -not $LAN) {
        throw "Could not identify WAN and LAN interfaces."
    }

    Write-Host "`nDetected WAN: $($WAN.Name)"
    Write-Host "Detected LAN: $($LAN.Name)"

    # =====================================================
    # DISPLAY CONFIGURATION
    # =====================================================

    Write-Host "`nPlanned configuration:"
    Write-Host "WAN: $($WAN.Name) - Existing configuration preserved"
    Write-Host "LAN: $($LAN.Name)"
    Write-Host "LAN IP: $InternalIP/$InternalPrefix"
    Write-Host "NAT network: $InternalNetwork"

    $Confirmation = Read-Host "`nContinue? (YES/NO)"

    if ($Confirmation -cne "YES") {
        throw "Deployment cancelled."
    }

    # =====================================================
    # CHECK WAN / LAN SUBNET CONFLICT
    # =====================================================

    $InternalAddress = [System.Net.IPAddress]::Parse($InternalIP)

    $InternalBytes = $InternalAddress.GetAddressBytes()

    $InternalMask = [System.Net.IPAddress]::Parse("255.255.255.0").
        GetAddressBytes()

    $WanAddresses = @(
        Get-NetIPAddress `
            -InterfaceIndex $WAN.ifIndex `
            -AddressFamily IPv4
    )

    foreach ($Address in $WanAddresses) {

        $WanIP = [System.Net.IPAddress]::Parse($Address.IPAddress)
        $WanBytes = $WanIP.GetAddressBytes()

        $SameSubnet = $true

        for ($i = 0; $i -lt 4; $i++) {
            if (
                ($WanBytes[$i] -band $InternalMask[$i]) -ne
                ($InternalBytes[$i] -band $InternalMask[$i])
            ) {
                $SameSubnet = $false
                break
            }
        }

        if ($SameSubnet) {
            throw "WAN and LAN address ranges overlap. Change the LAN network."
        }
    }

    # =====================================================
    # CONFIGURE LAN INTERFACE
    # =====================================================

    Write-Host "`nConfiguring LAN interface..."

    $ExistingAddress = Get-NetIPAddress `
        -InterfaceIndex $LAN.ifIndex `
        -AddressFamily IPv4 `
        -ErrorAction SilentlyContinue |
        Where-Object IPAddress -eq $InternalIP

    $OtherAddresses = @(
        Get-NetIPAddress `
            -InterfaceIndex $LAN.ifIndex `
            -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -ne $InternalIP -and
            $_.IPAddress -notlike "169.254.*"
        }
    )

    if ($OtherAddresses.Count -gt 0) {
        throw "LAN has another IPv4 address configured. Review it manually before continuing."
    }

    Set-NetIPInterface `
        -InterfaceIndex $LAN.ifIndex `
        -AddressFamily IPv4 `
        -Dhcp Disabled

    if (-not $ExistingAddress) {

        New-NetIPAddress `
            -InterfaceIndex $LAN.ifIndex `
            -IPAddress $InternalIP `
            -PrefixLength $InternalPrefix `
            -AddressFamily IPv4
    }

    # Remove any default gateway on LAN
    Get-NetRoute `
        -InterfaceIndex $LAN.ifIndex `
        -DestinationPrefix "0.0.0.0/0" `
        -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false

    # =====================================================
    # ENABLE IP FORWARDING
    # =====================================================

    Write-Host "`nEnabling IPv4 forwarding..."

    foreach ($Interface in @($WAN, $LAN)) {

        Set-NetIPInterface `
            -InterfaceIndex $Interface.ifIndex `
            -AddressFamily IPv4 `
            -Forwarding Enabled
    }

    # =====================================================
    # CREATE NAT
    # =====================================================

    Write-Host "`nChecking existing NAT configurations..."

    $ExistingNat = @(Get-NetNat -ErrorAction SilentlyContinue)

    $MatchingNat = $ExistingNat |
        Where-Object {
            $_.InternalIPInterfaceAddressPrefix -eq $InternalNetwork
        }

    if ($MatchingNat) {

        Write-Host "Matching NAT already exists. Reusing it."

    }
    elseif ($ExistingNat.Count -gt 0) {

        throw "Another WinNAT configuration exists. Automatic replacement is disabled."

    }
    else {

        Write-Host "Creating NAT..."

        New-NetNat `
            -Name $NatName `
            -InternalIPInterfaceAddressPrefix $InternalNetwork
    }

    # =====================================================
    # STARTUP CONFIGURATION
    # =====================================================

    Write-Host "`nChecking IP forwarding..."

    Get-NetIPInterface -AddressFamily IPv4 |
        Where-Object {
            $_.InterfaceIndex -in @($WAN.ifIndex, $LAN.ifIndex)
        } |
        Format-Table InterfaceAlias, Forwarding

    # =====================================================
    # VERIFICATION
    # =====================================================

    Write-Host "`n=== NAT CONFIGURATION ==="

    Get-NetNat |
        Format-Table Name, InternalIPInterfaceAddressPrefix

    Write-Host "`n=== LAN CONFIGURATION ==="

    Get-NetIPAddress `
        -InterfaceIndex $LAN.ifIndex `
        -AddressFamily IPv4 |
        Format-Table InterfaceAlias, IPAddress, PrefixLength

    Write-Host "`n=== WAN CONFIGURATION ==="

    Get-NetIPConfiguration `
        -InterfaceIndex $WAN.ifIndex

    Write-Host "`n=== CONNECTIVITY TEST ==="

    Test-NetConnection 1.1.1.1 -Port 443

    Write-Host "`nNAT router configuration completed." `
        -ForegroundColor Green

    Write-Host "Log: $LogDirectory\NAT-Router.log"

}
catch {

    Write-Host "`nERROR: $($_.Exception.Message)" `
        -ForegroundColor Red

    throw

}
finally {

    Stop-Transcript | Out-Null

}
