
#requires -Version 5.1
# Active Directory - Console Overview
# Nur lesende Abfragen, keine Dateien werden erstellt.

$ErrorActionPreference = "Continue"

try {
    Import-Module ActiveDirectory -ErrorAction Stop

    $Domain = Get-ADDomain -ErrorAction Stop
    $Forest = Get-ADForest -ErrorAction Stop

    function Show-Section {
        param([string]$Title)

        Write-Host "`n"
        Write-Host ("=" * 75) -ForegroundColor DarkCyan
        Write-Host "  $Title" -ForegroundColor Cyan
        Write-Host ("=" * 75) -ForegroundColor DarkCyan
    }

    function Show-Table {
        param(
            [string]$Title,
            [scriptblock]$Query,
            [int]$First = 15
        )

        Show-Section $Title

        try {
            $data = @(& $Query)

            if ($data.Count -gt 0) {
                $data |
                    Select-Object -First $First |
                    Format-Table -AutoSize |
                    Out-Host

                if ($data.Count -gt $First) {
                    Write-Host "... und $($data.Count - $First) weitere Eintraege." `
                        -ForegroundColor DarkYellow
                }

                Write-Host "Anzahl: $($data.Count)" -ForegroundColor Green
            }
            else {
                Write-Host "Keine Eintraege gefunden." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "Abfrage fehlgeschlagen: $($_.Exception.Message)" `
                -ForegroundColor Red
        }
    }

    # --------------------------------------------------
    # 1. Domain und Forest
    # --------------------------------------------------

    Show-Section "ACTIVE DIRECTORY - OVERVIEW"

    Write-Host "Zeitpunkt       : $(Get-Date)"
    Write-Host "Benutzer        : $env:USERDOMAIN\$env:USERNAME"
    Write-Host "Domain          : $($Domain.DNSRoot)"
    Write-Host "NetBIOS         : $($Domain.NetBIOSName)"
    Write-Host "Domain Mode     : $($Domain.DomainMode)"
    Write-Host "Forest          : $($Forest.Name)"
    Write-Host "Forest Mode     : $($Forest.ForestMode)"
    Write-Host "Root Domain     : $($Forest.RootDomain)"
    Write-Host "Domain SID      : $($Domain.DomainSID)"
    Write-Host "PDC Emulator    : $($Domain.PDCEmulator)"
    Write-Host "RID Master      : $($Domain.RIDMaster)"
    Write-Host "Infrastructure  : $($Domain.InfrastructureMaster)"
    Write-Host "Schema Master   : $($Forest.SchemaMaster)"
    Write-Host "Naming Master   : $($Forest.DomainNamingMaster)"

    # --------------------------------------------------
    # 2. Kennzahlen
    # --------------------------------------------------

    Show-Section "AD STATISTIKEN"

    $Users = @(Get-ADUser -Filter * -ResultSetSize $null)
    $Computers = @(Get-ADComputer -Filter * -ResultSetSize $null)
    $Groups = @(Get-ADGroup -Filter * -ResultSetSize $null)
    $OUs = @(Get-ADOrganizationalUnit -Filter * -ResultSetSize $null)
    $DCs = @(Get-ADDomainController -Filter *)

    $EnabledUsers = @($Users | Where-Object Enabled).Count
    $DisabledUsers = @($Users | Where-Object { !$_.Enabled }).Count
    $EnabledComputers = @($Computers | Where-Object Enabled).Count
    $DisabledComputers = @($Computers | Where-Object { !$_.Enabled }).Count

    [PSCustomObject]@{
        BenutzerGesamt       = $Users.Count
        BenutzerAktiv        = $EnabledUsers
        BenutzerDeaktiviert  = $DisabledUsers
        ComputerGesamt       = $Computers.Count
        ComputerAktiv        = $EnabledComputers
        ComputerDeaktiviert  = $DisabledComputers
        Gruppen              = $Groups.Count
        Organisationseinheiten = $OUs.Count
        DomainController     = $DCs.Count
    } | Format-List | Out-Host

    # --------------------------------------------------
    # 3. Domain Controller
    # --------------------------------------------------

    Show-Table "DOMAIN CONTROLLER" {
        Get-ADDomainController -Filter * |
            Select-Object HostName, IPv4Address, Site,
                OperatingSystem, IsGlobalCatalog, IsReadOnly,
                OperationMasterRoles
    } 30

    # --------------------------------------------------
    # 4. Benutzer
    # --------------------------------------------------

    Show-Table "LETZTE ANMELDUNGEN - BENUTZER" {
        Get-ADUser -Filter * -Properties LastLogonDate,
            Department, Enabled, EmailAddress |
            Sort-Object LastLogonDate -Descending |
            Select-Object SamAccountName, Name, Enabled,
                Department, EmailAddress, LastLogonDate
    } 20

    Show-Table "DEAKTIVIERTE BENUTZER" {
        Get-ADUser -Filter { Enabled -eq $false } |
            Select-Object Name, SamAccountName, DistinguishedName
    } 20

    Show-Table "GESPERRTE BENUTZER" {
        Search-ADAccount -LockedOut -UsersOnly |
            Select-Object Name, SamAccountName, LastLogonDate
    } 20

    Show-Table "INAKTIVE BENUTZER - 90 TAGE" {
        Search-ADAccount -AccountInactive -UsersOnly `
            -TimeSpan (New-TimeSpan -Days 90) |
            Select-Object Name, SamAccountName, LastLogonDate, Enabled
    } 20

    # --------------------------------------------------
    # 5. Gruppen
    # --------------------------------------------------

    Show-Table "WICHTIGE PRIVILEGIERTE GRUPPEN" {
        $Names = @(
            "Domain Admins",
            "Enterprise Admins",
            "Schema Admins",
            "Administrators",
            "Account Operators",
            "Server Operators",
            "Backup Operators",
            "Group Policy Creator Owners",
            "DnsAdmins"
        )

        foreach ($Name in $Names) {
            $Group = Get-ADGroup -Filter "Name -eq '$Name'" `
                -ErrorAction SilentlyContinue

            if ($Group) {
                Get-ADGroupMember -Identity $Group -ErrorAction SilentlyContinue |
                    Select-Object @{
                        Name = "Gruppe"
                        Expression = { $Group.Name }
                    }, Name, SamAccountName, ObjectClass
            }
        }
    } 50

    Show-Table "GRUPPEN - UEBERSICHT" {
        Get-ADGroup -Filter * -Properties GroupScope,
            GroupCategory, Description |
            Select-Object Name, GroupScope, GroupCategory, Description
    } 20

    # --------------------------------------------------
    # 6. Computer
    # --------------------------------------------------

    Show-Table "COMPUTER - INVENTAR" {
        Get-ADComputer -Filter * -Properties OperatingSystem,
            OperatingSystemVersion, LastLogonDate, IPv4Address, Enabled |
            Sort-Object Name |
            Select-Object Name, Enabled, OperatingSystem,
                OperatingSystemVersion, IPv4Address, LastLogonDate
    } 30

    # --------------------------------------------------
    # 7. Organisationseinheiten
    # --------------------------------------------------

    Show-Table "ORGANISATIONSEINHEITEN (OU)" {
        Get-ADOrganizationalUnit -Filter * |
            Select-Object Name, DistinguishedName
    } 30

    # --------------------------------------------------
    # 8. Kennwortrichtlinie
    # --------------------------------------------------

    Show-Section "STANDARD-KENNWORTRICHTLINIE"

    Get-ADDefaultDomainPasswordPolicy |
        Select-Object MinPasswordLength, ComplexityEnabled,
            PasswordHistoryCount, MinPasswordAge, MaxPasswordAge,
            LockoutThreshold, LockoutDuration,
            LockoutObservationWindow, ReversibleEncryptionEnabled |
        Format-List |
        Out-Host

    # --------------------------------------------------
    # 9. Gruppenrichtlinien
    # --------------------------------------------------

    Show-Section "GRUPPENRICHTLINIEN"

    try {
        Import-Module GroupPolicy -ErrorAction Stop

        $GPOs = @(Get-GPO -All)

        Write-Host "GPO Gesamt: $($GPOs.Count)" -ForegroundColor Green

        $GPOs |
            Select-Object DisplayName, GpoStatus, Owner,
                CreationTime, ModificationTime |
            Format-Table -AutoSize |
            Out-Host
    }
    catch {
        Write-Host "GroupPolicy-Modul nicht verfuegbar oder keine Berechtigung." `
            -ForegroundColor Yellow
    }

    # --------------------------------------------------
    # 10. Replikation
    # --------------------------------------------------

    Show-Table "REPLIKATIONSFEHLER" {
        Get-ADReplicationFailure -Target $Forest.Name -Scope Forest |
            Select-Object Server, Partner, FirstFailureTime,
                FailureCount, LastError
    } 30

    Show-Table "LETZTE REPLIKATION" {
        Get-ADReplicationPartnerMetadata -Target $Forest.Name `
            -Scope Forest |
            Select-Object Server, Partner, Partition,
                LastReplicationSuccess, LastReplicationResult,
                ConsecutiveReplicationFailures
    } 30

    # --------------------------------------------------
    # 11. Trusts und Sites
    # --------------------------------------------------

    Show-Table "DOMAIN TRUSTS" {
        Get-ADTrust -Filter * |
            Select-Object Name, Source, Target, Direction, TrustType
    } 30

    Show-Table "AD SITES" {
        Get-ADReplicationSite -Filter * |
            Select-Object Name, Description
    } 30

    Show-Table "AD SUBNETS" {
        Get-ADReplicationSubnet -Filter * |
            Select-Object Name, Site, Location
    } 30

    # --------------------------------------------------
    # Ende
    # --------------------------------------------------

    Show-Section "OVERVIEW ABGESCHLOSSEN"

    Write-Host "Alle Abfragen wurden beendet." -ForegroundColor Green
    Write-Host "Es wurden keine Berichtdateien erstellt." -ForegroundColor Green
}
catch {
    Write-Host "Fehler: $($_.Exception.Message)" -ForegroundColor Red
}
