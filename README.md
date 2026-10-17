<div align="center">

# ⚡ PSLib

### Die offene PowerShell-Bibliothek für Windows-Administration

Praxiserprobte, sofort einsetzbare PowerShell-Skripte für Admins, IT-Teams und Power-User.
Frei verfügbar, offen entwickelt und für jeden nutzbar.

[![Open Source](https://img.shields.io/badge/Open%20Source-❤-brightgreen)](#-open-source)
[![License: MIT](https://img.shields.io/badge/Lizenz-MIT-yellow.svg)](LICENSE)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4?logo=windows&logoColor=white)
[![PRs Welcome](https://img.shields.io/badge/PRs-willkommen-ff69b4.svg)](#-mitmachen)

[Skripte](#-skripte) · [Schnellstart](#-schnellstart) · [Mitmachen](#-mitmachen) · [Lizenz](#-lizenz)

</div>

---

## 📦 Was ist PSLib?

**PSLib** ist eine wachsende Sammlung von PowerShell-Skripten für alltägliche und knifflige Aufgaben in der Windows-Administration. Jedes Skript ist

- 🧱 **eigenständig**: keine externen Module, keine Abhängigkeiten
- 📝 **dokumentiert**: eigene README, Comment-Based Help (`Get-Help`) und Beispiele
- 🇩🇪 **deutschsprachig**: Ausgaben, Hilfe und Datumsformate für den DACH-Raum
- 🔍 **nachvollziehbar**: lesbarer Code statt Blackbox, damit du weißt, was auf deinem System passiert

---

## 🗂️ Skripte

| Skript | Kategorie | Beschreibung |
|---|---|---|
| [**Set-LogonNotice**](./Set-LogonNotice) | 🔐 Sicherheit | Setzt die Anmeldemeldung (Titel/Text) der lokalen Sicherheitsoptionen sofort, zeitgesteuert oder täglich wiederkehrend |
| *weitere folgen …* | | [Idee vorschlagen](../../issues) |

---

## 🚀 Schnellstart

```powershell
# Repository klonen
git clone https://github.com/<benutzer>/PSLib.git
cd PSLib

# Heruntergeladene Skripte entsperren
Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File

# Hilfe zu einem Skript anzeigen
Get-Help .\Set-LogonNotice\Set-LogonNotice.ps1 -Full
```

> [!TIP]
> Viele Skripte benötigen Administratorrechte. Starte PowerShell dafür mit **„Als Administrator ausführen“**.

---

## 🏗️ Aufbau

```text
PSLib/
├── README.md               ← du bist hier
├── LICENSE
├── CONTRIBUTING.md
└── Set-LogonNotice/
    ├── Set-LogonNotice.ps1
    └── README.md
```

Jedes Skript lebt in einem **eigenen Ordner** mit eigener README. So bleibt die Bibliothek übersichtlich und jedes Werkzeug lässt sich einzeln herunterladen.

---

## 💚 Open Source

PSLib ist **Open Source** und wird offen entwickelt. Das heißt für dich:

| | |
|---|---|
| ✅ **Kostenlos nutzen** | privat, im Unternehmen und kommerziell |
| ✅ **Anpassen** | Skripte verändern und an deine Umgebung anpassen |
| ✅ **Weitergeben** | teilen und in eigene Projekte einbauen |
| ✅ **Mitgestalten** | Fehler melden, Ideen einbringen und Code beisteuern |

Einzige Bedingung: Der Lizenz- und Copyright-Hinweis bleibt erhalten.

---

## 🤝 Mitmachen

Beiträge sind ausdrücklich willkommen, vom Tippfehler bis zum neuen Skript.

1. 🍴 Repository **forken**
2. 🌿 Branch anlegen: `git checkout -b feature/mein-skript`
3. 💾 Änderungen committen: `git commit -m "Neues Skript: Mein-Skript"`
4. 🚀 Branch pushen und einen **Pull Request** öffnen

### Richtlinien für neue Skripte

- [ ] Verb-Nomen-Benennung nach PowerShell-Standard (`Get-Verb`)
- [ ] Comment-Based Help mit `.SYNOPSIS`, `.DESCRIPTION` und `.EXAMPLE`
- [ ] Eigener Ordner mit `README.md`
- [ ] Keine externen Abhängigkeiten, wenn vermeidbar
- [ ] Datei als **UTF-8 mit BOM** speichern (Umlaute in PowerShell 5.1)
- [ ] Mit `PSScriptAnalyzer` geprüft

🐛 **Fehler gefunden?** [Issue öffnen](../../issues) und beschreiben, was passiert ist, was erwartet wurde und welche Windows- und PowerShell-Version du nutzt.

---

## ⚠️ Haftungsausschluss

> [!WARNING]
> Die Skripte verändern teilweise Systemeinstellungen (Registry, Aufgabenplanung, Sicherheitsrichtlinien). Teste sie **immer zuerst in einer Testumgebung**. Die Nutzung erfolgt auf eigene Verantwortung und ohne Gewährleistung.

---

## 📄 Lizenz

Veröffentlicht unter der **[MIT-Lizenz](LICENSE)**. Du darfst den Code frei verwenden, verändern und weitergeben.

---

<div align="center">

**Wenn dir PSLib hilft, lass einen ⭐ da!**

<sub>Mit ❤️ und PowerShell gebaut</sub>

</div>
