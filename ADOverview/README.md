
<div align="center">

# 🛡️ Active Directory Overview

### PowerShell-based Active Directory Inventory & Monitoring

Eine übersichtliche Konsolenübersicht deiner Active-Directory-Umgebung –  
ohne Report-Dateien, ohne Änderungen am Verzeichnisdienst.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Active Directory](https://img.shields.io/badge/Active%20Directory-RSAT-0078D4?logo=microsoft&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows&logoColor=white)
![Mode](https://img.shields.io/badge/Mode-Read--Only-2EA44F)
![License](https://img.shields.io/badge/License-MIT-blue)

</div>

---

## 📖 Inhaltsverzeichnis

- [Über das Projekt](#-über-das-projekt)
- [Features](#-features)
- [Voraussetzungen](#-voraussetzungen)
- [Installation](#-installation)
- [Verwendung](#-verwendung)
- [Übersicht der Module](#-übersicht-der-module)
- [Berechtigungen](#-berechtigungen)
- [Fehlerbehebung](#-fehlerbehebung)
- [Sicherheit und Datenschutz](#-sicherheit-und-datenschutz)
- [Bekannte Einschränkungen](#-bekannte-einschränkungen)
- [Roadmap](#-roadmap)

---

## 🎯 Über das Projekt

**Active Directory Overview** ist ein PowerShell-Skript zur schnellen Bestandsaufnahme einer Active-Directory-Domäne.

Es fasst wichtige Informationen über die AD-Infrastruktur, Benutzer, Computer, Gruppen, Gruppenrichtlinien und Replikation direkt in der PowerShell-Konsole zusammen.

Das Ziel ist eine schnelle, unkomplizierte Übersicht für Administratoren, IT-Techniker und Administratoren in Ausbildung.

### 💡 Grundprinzip

- Keine CSV-, JSON-, TXT- oder HTML-Reports
- Keine Installation zusätzlicher Reporting-Software
- Keine Änderungen an AD-Objekten
- Übersichtliche Konsolenausgabe
- Direkter Zugriff auf verfügbare AD-Informationen

> Das Skript ist ein administratives Inventarisierungswerkzeug. Es ersetzt keine vollständige Sicherheitsprüfung oder ein dediziertes Monitoring-System.

---

## ✨ Features

| Bereich | Beschreibung |
|---|---|
| 🏢 Domain & Forest | Domänenname, Forest, Funktionsebenen und SID |
| 🖥️ Domain Controller | Server, IP-Adressen, Sites und FSMO-Rollen |
| 👤 Benutzer | Konten, Status, Abteilung, E-Mail und letzte Anmeldung |
| 🔒 Account Security | Deaktivierte, gesperrte und inaktive Benutzer |
| 👥 Gruppen | Gruppenübersicht und Mitglieder privilegierter Gruppen |
| 💻 Computer | Betriebssystem, IP-Adresse und letzte Anmeldung |
| 🗂️ Organisationseinheiten | OUs und Distinguished Names |
| 🔑 Kennwortrichtlinien | Passwortlänge, Komplexität und Sperrregeln |
| ⚙️ Gruppenrichtlinien | GPO-Status, Besitzer und Änderungszeitpunkt |
| 🔄 Replikation | Replikationspartner, letzte erfolgreiche Replikation und Fehler |
| 🌐 Trusts & Sites | Vertrauensstellungen, AD-Sites und Subnetze |
| 📊 Statistiken | Anzahl der Benutzer, Computer, Gruppen und OUs |

---

## 🧰 Voraussetzungen

Vor der Verwendung sollten folgende Voraussetzungen erfüllt sein:

- Windows mit Windows PowerShell 5.1 oder einer kompatiblen PowerShell-Version
- Netzwerkzugriff auf mindestens einen Domain Controller
- Active-Directory-PowerShell-Modul (RSAT)
- Ein Domänenkonto mit Leserechten für die gewünschten Informationen

### Benötigte Module

| Modul | Verwendung |
|---|---|
| `ActiveDirectory` | Domäne, Benutzer, Gruppen, Computer und Replikation |
| `GroupPolicy` | Gruppenrichtlinienübersicht |

Das Modul `GroupPolicy` ist optional. Fehlt es, wird die GPO-Auswertung übersprungen.

### RSAT installieren

Öffne PowerShell mit administrativen Rechten auf einem unterstützten Windows-Client und führe aus:

```powershell
Add-WindowsCapability -Online `
  -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

Anschließend kannst du prüfen, ob das Modul verfügbar ist:

```powershell
Get-Module -ListAvailable ActiveDirectory
```

Optional:

```powershell
Get-Module -ListAvailable GroupPolicy
```

> Die Installation von RSAT benötigt administrative Rechte auf dem Client. Für normale AD-Abfragen sind lokale Administratorrechte nicht grundsätzlich erforderlich.

---

## 🚀 Installation

### 1. Repository oder Skript vorbereiten

Lege einen Ordner für das Projekt an:

```powershell
New-Item -ItemType Directory `
  -Path "$HOME\AD-Overview" -Force
```

Speichere das PowerShell-Skript in diesem Ordner unter:

```text
AD-Overview.ps1
```

Speichere diese Dokumentation daneben als:

```text
README.md
```

Die Projektstruktur sieht dann folgendermaßen aus:

```text
AD-Overview/
├── AD-Overview.ps1
└── README.md
```

### 2. Modul importieren

Öffne PowerShell und führe aus:

```powershell
Import-Module ActiveDirectory
```

Prüfe anschließend, ob deine Domäne erreichbar ist:

```powershell
Get-ADDomain
```

Wenn Domäneninformationen angezeigt werden, funktioniert die grundlegende Verbindung.

### 3. Skript starten

Wechsle in den Projektordner:

```powershell
Set-Location "$HOME\AD-Overview"
```

Starte das Skript:

```powershell
.\AD-Overview.ps1
```

Die Übersicht wird direkt in der aktuellen PowerShell-Sitzung ausgegeben.

### 4. Execution Policy

Falls PowerShell die Ausführung aufgrund der Execution Policy blockiert, prüfe zuerst die geltenden Richtlinien:

```powershell
Get-ExecutionPolicy -List
```

Für ein vertrauenswürdiges lokales Skript kann – sofern durch die Unternehmensrichtlinien erlaubt – die Richtlinie nur für die aktuelle Sitzung angepasst werden:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Danach:

```powershell
.\AD-Overview.ps1
```

Diese Einstellung gilt nur für die aktuelle PowerShell-Sitzung. Gruppenrichtlinien oder andere Sicherheitskontrollen können die Ausführung weiterhin verhindern.

---

## 🖥️ Verwendung

Nach dem Start arbeitet das Skript die vorgesehenen Bereiche nacheinander ab.

### Beispiel einer Konsolenausgabe

Die tatsächlichen Werte hängen von deiner Umgebung ab.

```text
===========================================================================
  ACTIVE DIRECTORY - OVERVIEW
===========================================================================

Zeitpunkt       : 23.10.2026 16:30:00
Benutzer        : CONTOSO\administrator
Domain          : contoso.local
NetBIOS         : CONTOSO
Domain Mode     : Windows2016Domain
Forest          : contoso.local
Forest Mode     : Windows2016Forest
PDC Emulator    : DC01.contoso.local

===========================================================================
  AD STATISTIKEN
===========================================================================

BenutzerGesamt         : 420
BenutzerAktiv          : 385
BenutzerDeaktiviert    : 35
ComputerGesamt         : 160
ComputerAktiv          : 142
ComputerDeaktiviert    : 18
Gruppen                : 95
Organisationseinheiten : 24
DomainController       : 2

===========================================================================
  DOMAIN CONTROLLER
===========================================================================

HostName               IPv4Address    Site
--------               -----------    ----
DC01.contoso.local     192.168.1.10   HQ
DC02.contoso.local     192.168.2.10   Branch

===========================================================================
  OVERVIEW ABGESCHLOSSEN
===========================================================================

Alle Abfragen wurden beendet.
Es wurden keine Berichtdateien erstellt.
```

**Hinweis:** Diese Ausgabe ist ein fiktives Beispiel zur Veranschaulichung. Sie zeigt keine tatsächlichen Daten deiner Umgebung.

---

## 📚 Übersicht der Module

### 🏢 Domain & Forest

Zeigt grundlegende Informationen über die Active-Directory-Infrastruktur:

- DNS-Domänenname und NetBIOS-Name
- Forest und Root Domain
- Domain- und Forest-Funktionsebene
- Domain SID
- FSMO-Rollen

Die FSMO-Rollen sind wichtig, um zu verstehen, welche Domain Controller bestimmte zentrale Aufgaben übernehmen.

### 🖥️ Domain Controller

Die Übersicht enthält unter anderem:

- Hostname und IPv4-Adresse
- Zugehörige AD-Site
- Betriebssystem
- Global-Catalog-Status
- Read-only-Status
- Zugewiesene FSMO-Rollen

### 👤 Benutzerverwaltung

Die Benutzerübersicht enthält unter anderem:

- SamAccountName und Anzeigename
- Aktivierungsstatus
- Abteilung und E-Mail-Adresse
- Letzte bekannte Anmeldung

Zusätzliche Abfragen zeigen deaktivierte, gesperrte und länger inaktive Konten.

**Wichtig:** Ein inaktives Konto ist nicht automatisch ein überflüssiges Konto. Servicekonten, längere Abwesenheiten und spezielle Betriebsabläufe müssen berücksichtigt werden.

### 👥 Gruppen und privilegierte Mitglieder

Das Skript zeigt allgemeine Gruppeninformationen und versucht, Mitglieder ausgewählter privilegierter Gruppen auszulesen, zum Beispiel:

- Domain Admins
- Enterprise Admins
- Schema Admins
- Administrators
- Backup Operators
- DNSAdmins

Die Liste ist nicht vollständig und berücksichtigt nicht automatisch alle indirekten Berechtigungen oder verschachtelten Gruppenmitgliedschaften.

### 💻 Computer

Die Computerübersicht umfasst:

- Computernamen
- Aktivierungsstatus
- Betriebssystem und Version
- IPv4-Adresse, sofern verfügbar
- Letzte bekannte Anmeldung

Die IP-Adresse ist ein AD-Attribut und muss nicht dem aktuellen Netzwerkzustand entsprechen.

### 🗂️ Organisationseinheiten

Die OU-Ausgabe hilft dir, die Struktur der Domäne zu verstehen.

Sie zeigt Namen und Distinguished Names der Organisationseinheiten. Sie stellt jedoch nicht automatisch die vollständige Vererbung von Gruppenrichtlinien oder delegierte Berechtigungen dar.

### 🔑 Kennwortrichtlinien

Angezeigt werden unter anderem:

- Mindestkennwortlänge
- Kennwortkomplexität
- Kennwortverlauf
- Maximales Kennwortalter
- Kontosperrschwelle
- Sperrdauer

Die Ausgabe zeigt die Standardrichtlinie der Domäne. Feingranulare Kennwortrichtlinien (Fine-Grained Password Policies) werden in der aktuellen Version nicht vollständig ausgewertet.

### ⚙️ Gruppenrichtlinien

Wenn das `GroupPolicy`-Modul verfügbar ist, zeigt das Skript:

- Name der GPO
- Status
- Besitzer
- Erstellungszeitpunkt
- Zeitpunkt der letzten Änderung

Es erstellt keine HTML-Berichte und exportiert keine Dateien.

### 🔄 Replikation

Die Replikationsabfragen zeigen erkannte Fehler und Metadaten der Replikationspartner.

Achte insbesondere auf:

- Wiederholte Replikationsfehler
- Fehlende erfolgreiche Replikationen
- Hohe Anzahl aufeinanderfolgender Fehler
- Unerwartet alte Zeitpunkte der letzten erfolgreichen Replikation

Ein einzelner Fehler muss nicht automatisch auf einen kritischen Defekt hindeuten. Netzwerkprobleme, Wartungsfenster und nicht erreichbare Partner müssen in die Bewertung einbezogen werden.

### 🌐 Trusts und Sites

Diese Bereiche zeigen:

- AD-Trusts
- Vertrauensrichtung und Trust-Typ
- AD-Sites
- AD-Subnetze und deren Zuordnung

Damit lassen sich grundlegende Informationen zur logischen und standortbezogenen AD-Struktur überprüfen.

---

## 🔐 Berechtigungen

Das Skript ist für administrative Lesezugriffe ausgelegt.

| Aktion | Typische Voraussetzung |
|---|---|
| Domäne und Forest lesen | Authentifiziertes Domänenkonto |
| Benutzer und Gruppen auflisten | Leserechte auf die jeweiligen Objekte |
| Gruppenmitgliedschaften auslesen | Leserechte auf Gruppen und Mitglieder |
| GPOs auflisten | Zugriff auf die entsprechenden GPO-Informationen |
| DNS-Zonen analysieren | DNS-Modul und ausreichende Leserechte |
| Replikationsstatus auslesen | Erreichbare DCs und erforderliche Leseberechtigungen |

Ein Konto mit Domain-Admin-Rechten ist für eine grundlegende Übersicht nicht zwingend erforderlich. Verwende möglichst ein Konto mit minimal notwendigen Berechtigungen.

---

## 🧯 Fehlerbehebung

### Fehler: `Get-ADDomain` wird nicht erkannt

**Ursache:** Das Active-Directory-Modul ist nicht installiert oder nicht geladen.

**Lösung:**

```powershell
Import-Module ActiveDirectory
Get-Command Get-ADDomain
```

### Fehler: `Unable to contact the server`

**Mögliche Ursachen:**

- Keine Netzwerkverbindung zum Domain Controller
- DNS-Auflösung funktioniert nicht
- VPN-Verbindung fehlt
- Firewall blockiert die benötigte Kommunikation
- Keine gültige Domänenanmeldung

Prüfe die DNS-Konfiguration:

```powershell
Resolve-DnsName (Get-ADDomain).DNSRoot
```

Teste die DC-Ermittlung:

```powershell
nltest /dsgetdc:$env:USERDNSDOMAIN
```

### Fehler: Zugriff verweigert

Prüfe, ob dein Konto Zugriff auf die betroffenen Objekte und Abfragen besitzt.

```powershell
whoami
Get-ADDomain
```

Verwende nicht automatisch ein privilegierteres Konto, sondern kläre zunächst, welche Berechtigung tatsächlich fehlt.

### Fehler: Das GroupPolicy-Modul fehlt

Prüfe die Verfügbarkeit:

```powershell
Get-Module -ListAvailable GroupPolicy
```

Falls erforderlich, installiere die entsprechende RSAT-Komponente. Die übrigen AD-Bereiche können unabhängig davon funktionieren.

### Fehler: Die Ausgabe ist sehr umfangreich

Die Benutzer-, Gruppen- und Computerübersichten sind auf eine begrenzte Anzahl sichtbarer Einträge ausgelegt.

Wenn du die gesamte Ausgabe eines bestimmten Bereichs sehen möchtest, kannst du die entsprechende Abfrage einzeln ausführen:

```powershell
Get-ADUser -Filter * |
    Select-Object Name, SamAccountName, Enabled |
    Format-Table -AutoSize
```

---

## 🛡️ Sicherheit und Datenschutz

Dieses Skript ist für eine Bestandsaufnahme gedacht und nimmt selbst keine Änderungen an AD-Objekten vor.

Beachte dennoch folgende Punkte:

- Die Ausgabe enthält interne Infrastrukturinformationen und personenbezogene Daten.
- Gruppenmitgliedschaften können sicherheitsrelevante Informationen offenlegen.
- Führe das Skript nur in Umgebungen aus, für die du autorisiert bist.
- Veröffentliche keine unbereinigten Konsolenausgaben in öffentlichen Repositories oder Tickets.
- Verwende keine unnötig privilegierten Konten.
- Bewerte auffällige Konten oder Replikationsfehler immer im Kontext deiner Umgebung.

> **Read-only bedeutet nicht risikofrei:** Umfangreiche LDAP-Abfragen erzeugen Netzwerk- und DC-Last. Führe große Inventarisierungen kontrolliert durch, insbesondere in produktiven Umgebungen.

---

## ⚠️ Bekannte Einschränkungen

Die aktuelle Version ist bewusst als einfache Konsolenübersicht gehalten.

- Keine persistenten Reports oder automatischen Exporte
- Keine automatische Bewertung der Sicherheitslage
- Keine vollständige Analyse verschachtelter Gruppenrechte
- Keine garantierte Echtzeit-Aussage zur letzten Benutzeranmeldung
- Keine vollständige Auswertung aller GPO-Einstellungen
- Keine vollständige Analyse von Delegationen oder ACLs
- Keine umfassende Prüfung aller DNS- oder Trust-Konfigurationen

Die Ausgabe ist daher als Überblick zu verstehen und nicht als vollständiger Auditbericht.

---

## 🗺️ Roadmap

Mögliche Erweiterungen für zukünftige Versionen:

- [ ] Interaktives Konsolenmenü
- [ ] Filter für einzelne Benutzer, Gruppen und Computer
- [ ] Separate Analyse privilegierter Gruppen
- [ ] Prüfung veralteter Computerobjekte
- [ ] Anzeige feingranularer Kennwortrichtlinien
- [ ] GPO-Verknüpfungen und Vererbungsanalyse
- [ ] Analyse von OU-Delegationen und ACLs
- [ ] Optionale Farbcodierung für kritische Befunde
- [ ] Laufzeit- und Performanceoptimierungen

---

## 📄 Lizenz

Wenn du das Skript als öffentliches Projekt veröffentlichen möchtest, kannst du eine Lizenz ergänzen. Das Badge oben ist nur eine Projektvorlage und bedeutet nicht, dass das Projekt bereits unter der MIT-Lizenz veröffentlicht wurde.

---

<div align="center">

**Active Directory Overview**

*Know your directory. Understand your infrastructure.*

</div>
