#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Setzt die Sicherheitsoptionen
      "Interaktive Anmeldung: Nachrichtentitel für Benutzer, die sich anmelden möchten"
      "Interaktive Anmeldung: Nachrichtentext für Benutzer, die sich anmelden möchten"
    sofort oder zeitgesteuert (über geplante Aufgaben als SYSTEM).

.DESCRIPTION
    Aktionen:
      Set         Meldung sofort setzen (Titel/Text als Parameter oder aus gespeicherter Konfiguration)
      Clear       Meldung sofort entfernen
      Schedule    Meldung ab -Start anzeigen und (optional) ab -End wieder entfernen
      Unschedule  Geplante Aufgaben löschen und Meldung entfernen
      Status      Aktuelle Werte und geplante Aufgaben anzeigen

    Platzhalter im Titel/Text (werden beim Setzen ersetzt):
      {DATUM} {ZEIT} {COMPUTER}       aktuelles Datum / Uhrzeit / Computername
      {START} {ENDE}                  Start / Ende als "dd.MM.yyyy HH:mm"
      {STARTZEIT} {ENDZEIT}           Start / Ende als "HH:mm"
    Zeilenumbrüche im Text: `n oder \n

.EXAMPLE
    .\Set-LogonNotice.ps1 -Action Set -Title "Hinweis" -Text "Nur für autorisierte Benutzer."

.EXAMPLE
    # Wartungshinweis vom 24.10. 18:00 bis 25.10. 06:00, danach automatisch entfernen
    .\Set-LogonNotice.ps1 -Action Schedule -Start "24.10.2026 18:00" -End "25.10.2026 06:00" `
        -Title "Wartungsarbeiten" -Text "Wartung bis {ENDE}.\nBitte nicht abmelden."

.EXAMPLE
    # Jeden Tag von 20:00 bis 07:00 anzeigen
    .\Set-LogonNotice.ps1 -Action Schedule -Daily -Start "20:00" -End "07:00" `
        -Title "Außerhalb der Arbeitszeit" -Text "Anmeldungen werden protokolliert."

.NOTES
    Registry: HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
              legalnoticecaption / legalnoticetext
    Hinweis: Eine Domänen-GPO, die diese Optionen ebenfalls setzt, überschreibt die Werte
    beim nächsten gpupdate.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Set', 'Clear', 'Schedule', 'Unschedule', 'Status')]
    [string]$Action,

    [string]$Title,
    [string]$Text,

    # Als String, damit deutsche Datumsangaben (24.10.2026 18:00) korrekt gelesen werden
    [string]$Start,
    [string]$End,

    [switch]$Daily,

    # Intern: von der Entfernen-Aufgabe genutzt, um einmalige Aufgaben aufzuräumen
    [switch]$RemoveTasks
)

$ErrorActionPreference = 'Stop'

$RegPath    = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$BaseDir    = Join-Path $env:ProgramData 'LogonNotice'
$ConfigFile = Join-Path $BaseDir 'config.json'
$LogFile    = Join-Path $BaseDir 'LogonNotice.log'
$ScriptCopy = Join-Path $BaseDir 'Set-LogonNotice.ps1'
$TaskPath   = '\LogonNotice\'
$TaskSet    = 'LogonNotice-Set'
$TaskClear  = 'LogonNotice-Clear'

# ---------------------------------------------------------------- Hilfsfunktionen

function Initialize-BaseDir {
    if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }
}

function Write-Log([string]$Message) {
    Initialize-BaseDir
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function ConvertTo-DateTime([string]$Value, [string]$Name) {
    $cultures = @([Globalization.CultureInfo]::CurrentCulture,
                  [Globalization.CultureInfo]::GetCultureInfo('de-DE'),
                  [Globalization.CultureInfo]::InvariantCulture)
    foreach ($c in $cultures) {
        $dt = [datetime]::MinValue
        if ([datetime]::TryParse($Value, $c, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$dt)) { return $dt }
    }
    throw "Ungültige Zeitangabe für -$Name : '$Value' (Beispiel: '24.10.2026 18:00' oder '20:00')"
}

function Get-Config {
    if (Test-Path $ConfigFile) {
        return Get-Content -Path $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Expand-Placeholders([string]$s, $cfg) {
    if ([string]::IsNullOrEmpty($s)) { return $s }
    $now = Get-Date
    $s = $s -replace '\\n', "`r`n"
    $s = $s -replace '(?<!\r)\n', "`r`n"
    $map = @{
        '{DATUM}'     = $now.ToString('dd.MM.yyyy')
        '{ZEIT}'      = $now.ToString('HH:mm')
        '{COMPUTER}'  = $env:COMPUTERNAME
        '{START}'     = if ($cfg) { $cfg.StartText } else { '' }
        '{ENDE}'      = if ($cfg) { $cfg.EndText }   else { '' }
        '{STARTZEIT}' = if ($cfg) { $cfg.StartTime } else { '' }
        '{ENDZEIT}'   = if ($cfg) { $cfg.EndTime }   else { '' }
    }
    foreach ($k in $map.Keys) { $s = $s.Replace($k, [string]$map[$k]) }
    return $s
}

function Set-Notice([string]$Caption, [string]$Body) {
    if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
    New-ItemProperty -Path $RegPath -Name 'legalnoticecaption' -Value $Caption -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegPath -Name 'legalnoticetext'    -Value $Body    -PropertyType String -Force | Out-Null
}

function Clear-Notice {
    Set-Notice -Caption '' -Body ''
}

function Remove-NoticeTasks {
    foreach ($t in $TaskSet, $TaskClear) {
        if (Get-ScheduledTask -TaskName $t -TaskPath $TaskPath -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $t -TaskPath $TaskPath -Confirm:$false
        }
    }
}

# ---------------------------------------------------------------- Aktionen

switch ($Action) {

    'Set' {
        $cfg = Get-Config
        if (-not $PSBoundParameters.ContainsKey('Title') -and $cfg) { $Title = $cfg.Title }
        if (-not $PSBoundParameters.ContainsKey('Text')  -and $cfg) { $Text  = $cfg.Text }
        if ([string]::IsNullOrWhiteSpace($Title) -and [string]::IsNullOrWhiteSpace($Text)) {
            throw 'Kein Titel/Text angegeben und keine gespeicherte Konfiguration gefunden.'
        }
        $t = Expand-Placeholders $Title $cfg
        $x = Expand-Placeholders $Text  $cfg
        Set-Notice -Caption $t -Body $x
        Write-Log "Anmeldemeldung gesetzt: '$t'"
    }

    'Clear' {
        Clear-Notice
        Write-Log 'Anmeldemeldung entfernt.'
        if ($RemoveTasks) {
            Remove-NoticeTasks
            Write-Log 'Einmalige geplante Aufgaben entfernt.'
        }
    }

    'Schedule' {
        if (-not $Start) { throw 'Für -Action Schedule ist -Start erforderlich.' }
        if ([string]::IsNullOrWhiteSpace($Title) -and [string]::IsNullOrWhiteSpace($Text)) {
            throw 'Für -Action Schedule sind -Title und/oder -Text erforderlich.'
        }

        $startDt = ConvertTo-DateTime $Start 'Start'
        $endDt   = if ($End) { ConvertTo-DateTime $End 'End' } else { $null }

        if (-not $Daily -and $endDt -and $endDt -le $startDt) {
            throw '-End muss nach -Start liegen.'
        }
        if (-not $Daily -and $endDt -and $endDt -le (Get-Date)) {
            throw '-End liegt in der Vergangenheit.'
        }

        Initialize-BaseDir

        # Skript an festen Ort kopieren, damit die Aufgaben unabhängig vom Ablageort funktionieren
        if ($PSCommandPath -and ((Resolve-Path $PSCommandPath).Path -ne $ScriptCopy)) {
            Copy-Item -Path $PSCommandPath -Destination $ScriptCopy -Force
        }

        $cfg = [ordered]@{
            Title     = $Title
            Text      = $Text
            Daily     = [bool]$Daily
            StartText = $startDt.ToString('dd.MM.yyyy HH:mm')
            EndText   = if ($endDt) { $endDt.ToString('dd.MM.yyyy HH:mm') } else { '' }
            StartTime = $startDt.ToString('HH:mm')
            EndTime   = if ($endDt) { $endDt.ToString('HH:mm') } else { '' }
        }
        $cfg | ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding UTF8

        # Konfiguration nur für Administratoren und SYSTEM lesbar/schreibbar machen
        & icacls.exe $BaseDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null

        Remove-NoticeTasks

        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                        -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        $psArgs    = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptCopy`""

        $trigSet = if ($Daily) { New-ScheduledTaskTrigger -Daily -At $startDt } else { New-ScheduledTaskTrigger -Once -At $startDt }
        Register-ScheduledTask -TaskName $TaskSet -TaskPath $TaskPath -Principal $principal -Settings $settings `
            -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "$psArgs -Action Set") `
            -Trigger $trigSet -Description 'Setzt die Anmeldemeldung (Sicherheitsoptionen).' | Out-Null

        if ($endDt) {
            $clearArgs = if ($Daily) { "$psArgs -Action Clear" } else { "$psArgs -Action Clear -RemoveTasks" }
            $trigClear = if ($Daily) { New-ScheduledTaskTrigger -Daily -At $endDt } else { New-ScheduledTaskTrigger -Once -At $endDt }
            Register-ScheduledTask -TaskName $TaskClear -TaskPath $TaskPath -Principal $principal -Settings $settings `
                -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $clearArgs) `
                -Trigger $trigClear -Description 'Entfernt die Anmeldemeldung (Sicherheitsoptionen).' | Out-Null
        }

        Write-Log ("Zeitplan angelegt: {0} ab {1}{2}" -f `
            ($(if ($Daily) { 'täglich' } else { 'einmalig' })),
            ($(if ($Daily) { $cfg.StartTime } else { $cfg.StartText })),
            ($(if ($endDt) { ' bis ' + $(if ($Daily) { $cfg.EndTime } else { $cfg.EndText }) } else { ' (ohne Ende)' })))

        # Liegt "jetzt" bereits im Zeitfenster? Dann sofort setzen.
        $now = Get-Date
        $inWindow = $false
        if ($Daily) {
            $s = $startDt.TimeOfDay; $n = $now.TimeOfDay
            if (-not $endDt)              { $inWindow = $n -ge $s }
            elseif ($s -lt $endDt.TimeOfDay) { $inWindow = ($n -ge $s -and $n -lt $endDt.TimeOfDay) }
            else                          { $inWindow = ($n -ge $s -or $n -lt $endDt.TimeOfDay) }   # über Mitternacht
        } else {
            $inWindow = ($now -ge $startDt) -and (-not $endDt -or $now -lt $endDt)
        }
        if ($inWindow) {
            $c = Get-Config
            Set-Notice -Caption (Expand-Placeholders $c.Title $c) -Body (Expand-Placeholders $c.Text $c)
            Write-Log 'Aktuelle Zeit liegt im Zeitfenster – Meldung sofort gesetzt.'
        }
    }

    'Unschedule' {
        Remove-NoticeTasks
        Clear-Notice
        Write-Log 'Geplante Aufgaben gelöscht und Anmeldemeldung entfernt.'
    }

    'Status' {
        $p = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
        Write-Host "`n--- Aktuelle Sicherheitsoptionen ---" -ForegroundColor Cyan
        Write-Host ("Titel: {0}" -f $(if ($p.legalnoticecaption) { $p.legalnoticecaption } else { '(leer)' }))
        Write-Host ("Text : {0}" -f $(if ($p.legalnoticetext)    { $p.legalnoticetext }    else { '(leer)' }))

        Write-Host "`n--- Geplante Aufgaben ---" -ForegroundColor Cyan
        $tasks = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue
        if ($tasks) {
            $tasks | ForEach-Object {
                $i = $_ | Get-ScheduledTaskInfo
                [pscustomobject]@{
                    Aufgabe        = $_.TaskName
                    Status         = $_.State
                    'Nächster Lauf' = $i.NextRunTime
                    'Letzter Lauf'  = $i.LastRunTime
                    Ergebnis       = $i.LastTaskResult
                }
            } | Format-Table -AutoSize
        } else {
            Write-Host '(keine)'
        }
        if (Test-Path $LogFile) {
            Write-Host "--- Protokoll (letzte 5 Einträge): $LogFile ---" -ForegroundColor Cyan
            Get-Content $LogFile -Tail 5 -Encoding UTF8
        }
    }
}
