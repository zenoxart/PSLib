

# 🛠️ Windows User \& Group Management



!\[PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell\&logoColor=white)
a
!\[Platform](https://img.shields.io/badge/Platform-Windows-0078D4?logo=windows\&logoColor=white)

!\[License](https://img.shields.io/badge/License-MIT-green.svg)

!\[Status](https://img.shields.io/badge/Status-In%20Entwicklung-orange)



Ein PowerShell-Skript zur Verwaltung lokaler Windows-Benutzer und

\-Benutzergruppen. Es ermöglicht das Erstellen, Aktivieren und Sperren

von Benutzerkonten sowie die Verwaltung von Gruppenmitgliedschaften,

Anmeldezeiten und Sicherheitskennungen (SIDs).



\## 📑 Inhaltsverzeichnis



\- \[✨ Features](#-features)

\- \[⚙️ Voraussetzungen](#️-voraussetzungen)

\- \[🚀 Installation und Ausführung](#-installation-und-ausführung)

\- \[🧩 Konfiguration](#-konfiguration)

\- \[📚 Funktionen im Überblick](#-funktionen-im-überblick)

\- \[🔐 Sicherheitshinweise](#-sicherheitshinweise)

\- \[🗺️ Benutzerprofil und Registry](#️-benutzerprofil-und-registry)

\- \[📝 Hinweise](#-hinweise)



\## ✨ Features



\- 👤 Lokale Windows-Benutzer erstellen und abfragen

\- 🔓 Benutzerkonten aktivieren und deaktivieren

\- ⏰ Anmeldezeiten konfigurieren

\- 👥 Lokale Gruppen erstellen und löschen

\- ➕ Benutzer zu lokalen Gruppen hinzufügen

\- 📋 Gruppenmitglieder anzeigen

\- 🆔 Security Identifier (SID) eines Benutzers ermitteln

\- 🗂️ Informationen zu Benutzerprofilen in der Windows-Registry finden



\## ⚙️ Voraussetzungen



\- Windows 10/11 oder Windows Server mit Unterstützung für die

&#x20; verwendeten LocalAccounts-Cmdlets

\- Windows PowerShell 5.1 oder eine kompatible PowerShell-Version

\- Administratorrechte für administrative Änderungen

\- Das PowerShell-Modul `Microsoft.PowerShell.LocalAccounts`



> \*\*Hinweis:\*\* Das Modul `Microsoft.PowerShell.LocalAccounts` ist in

> 32-Bit-PowerShell auf einem 64-Bit-System nicht verfügbar.

> Die Unterstützung unter PowerShell 7 hängt von der Umgebung ab.



\## 🚀 Installation und Ausführung



1\. Speichere das Skript beispielsweise als `UserManagement.ps1`.

2\. Öffne PowerShell mit administrativen Rechten.

3\. Wechsle in das Verzeichnis der Skriptdatei.

4\. Führe das Skript aus:



```powershell

.\\UserManagement.ps1

```



Falls die Ausführungsrichtlinie die Ausführung verhindert, prüfe

zunächst die geltende Richtlinie. Eine temporäre Ausführung kann

beispielsweise so erfolgen:



```powershell

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

```



Verwende diese Einstellung nur, wenn du der Skriptquelle vertraust.



\## 🧩 Konfiguration



Die wichtigsten Einstellungen werden am Anfang des Skripts definiert:



```powershell

$username = "Max"

$userfullname = "Max Mustermann"

$groupname = "Coder"

$groupdescription = "Alle Rechte für das Entwickeln von Apps"

$worktime = "Mo-Fr,07:00-19:00"

```



| Variable | Beschreibung | Beispiel |

|---|---|---|

| `$username` | Benutzername des lokalen Kontos | `Max` |

| `$userfullname` | Vollständiger Name | `Max Mustermann` |

| `$groupname` | Name der zu verwaltenden Gruppe | `Coder` |

| `$groupdescription` | Beschreibung der Gruppe | `Alle Rechte für das Entwickeln von Apps` |

| `$worktime` | Gewünschte Anmeldezeiten | `Mo-Fr,07:00-19:00` |



\*\*Wichtig:\*\* Die Anmeldezeiten müssen im von `net user` unterstützten

Format angegeben werden. Prüfe die Syntax und die zulässigen

Zeitintervalle für die verwendete Windows-Version.



\## 📚 Funktionen im Überblick



\### 👤 Benutzer erstellen



```powershell

New-LocalUser -Name $username `

&#x20;   -NoPassword `

&#x20;   -AccountNeverExpires `

&#x20;   -Description "Praktikant" `

&#x20;   -FullName $userfullname

```



Erstellt ein lokales Benutzerkonto ohne Kennwort und ohne automatisches

Ablaufen des Kontos.



> \*\*Sicherheit:\*\* Ein Konto ohne Kennwort ist für den produktiven Einsatz

> in der Regel ungeeignet. Verwende eine sichere Kennwortvergabe oder

> eine geeignete Identitätsverwaltung.



\### 🔎 Benutzerinformationen anzeigen



```powershell

Get-LocalUser -Name $username

Net User $username

```



Zeigt verfügbare Informationen zum lokalen Benutzerkonto an.



\### 🔓 Benutzer aktivieren



```powershell

Enable-LocalUser -Name $username

```



Aktiviert ein zuvor deaktiviertes lokales Benutzerkonto.



\### 🔒 Benutzer deaktivieren



```powershell

Disable-LocalUser -Name $username

```



Deaktiviert das Benutzerkonto, ohne es zu löschen.



\### ⏰ Anmeldezeiten festlegen



```powershell

net user $username /times:$worktime

```



Beschränkt die zulässigen Anmeldezeiten gemäß den von Windows

unterstützten Zeitangaben.



\*\*Achtung:\*\* Prüfe die tatsächlich akzeptierte Syntax. Das Beispiel

`Mo-Fr,07:00-19:00` ist nicht zwingend in jeder Windows-Konfiguration

gültig. Die Beschränkung ersetzt außerdem keine weiteren

Sicherheitsmaßnahmen.



\### 👥 Lokale Gruppe verwalten



\*\*Gruppe erstellen:\*\*



```powershell

New-LocalGroup -Name $groupname -Description $groupdescription

```



\*\*Gruppe löschen:\*\*



```powershell

Remove-LocalGroup -Name $groupname

```



\*\*Benutzer hinzufügen:\*\*



```powershell

Add-LocalGroupMember -Group $groupname -Member $username

```



\*\*Mitglieder anzeigen:\*\*



```powershell

Get-LocalGroupMember -Group $groupname

```



> \*\*Achtung:\*\* Das Löschen einer Gruppe kann bestehende Berechtigungs-

> und Verwaltungsstrukturen beeinflussen. Prüfe vorab, ob die Gruppe

> noch benötigt wird.



\### 🆔 SID eines Benutzers ermitteln



```powershell

$objUser = New-Object System.Security.Principal.NTAccount($username)

$sid = $objUser.Translate(

&#x20;   \[System.Security.Principal.SecurityIdentifier]

)



Write-Output "SID: $($sid.Value)"

```



Eine SID (Security Identifier) ist eine eindeutige Sicherheitskennung,

die Windows zur Identifikation von Sicherheitsprinzipalen verwendet.



> \*\*Hinweis:\*\* Die Übersetzung eines unqualifizierten Namens wie `Max`

> kann abhängig vom Kontext fehlschlagen oder einen anderen

> Namensbereich auflösen. Bei lokalen Konten kann die explizite

> Angabe des Computernamens erforderlich sein.



\## 🔐 Sicherheitshinweise



\- Führe administrative Änderungen nur mit den erforderlichen

&#x20; Berechtigungen aus.

\- Verwende nach Möglichkeit Konten mit sicheren Kennwörtern.

\- Vermeide unnötige Mitgliedschaften in privilegierten Gruppen.

\- Prüfe Gruppenänderungen und Anmeldebeschränkungen vor dem Einsatz.

\- Beachte, dass das Skript bestehende Gruppen löscht, bevor es sie

&#x20; neu erstellt, sofern der Ablauf unverändert bleibt.

\- Teste Änderungen zunächst in einer isolierten Testumgebung.



\## 🗺️ Benutzerprofil und Registry



Benutzerbezogene Profilinformationen können unter folgendem

Registry-Pfad gefunden werden:



```text

HKEY\_LOCAL\_MACHINE

└── SOFTWARE

&#x20;   └── Microsoft

&#x20;       └── Windows NT

&#x20;           └── CurrentVersion

&#x20;               └── ProfileList

```



Die Unterschlüssel unter `ProfileList` sind üblicherweise nach SIDs

benannt. Der Wert `ProfileImagePath` verweist häufig auf den zugehörigen

Profilpfad.



\*\*Wichtig:\*\* Das Erstellen eines Benutzerkontos erzeugt nicht in jedem

Fall sofort ein vollständig initialisiertes Benutzerprofil.



\## 📝 Hinweise



\- `New-LocalUser -NoPassword` erstellt ein Konto ohne Kennwort.

\- `Enable-LocalUser` und `Disable-LocalUser` steuern den Aktivierungsstatus.

\- `Add-LocalGroupMember` verwaltet Mitgliedschaften lokaler Gruppen.

\- Die Gruppe `Benutzer` ist der lokalisierte Name der Windows-Gruppe

&#x20; `Users`. Auf anderen Windows-Sprachversionen kann der Name abweichen.

\- Das Skript ist eine Sammlung von Verwaltungsbefehlen und noch keine

&#x20; vollständig abgesicherte, idempotente Verwaltungsroutine.



\---



\*\*Autor:\*\* Max Mustermann  

\*\*Projekt:\*\* Windows User \& Group Management  

\*\*Technologie:\*\* PowerShell

&#x20;

