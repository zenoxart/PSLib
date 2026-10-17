<div align="center">

# 🔐 Set-LogonNotice

**Zeitgesteuerte Anmeldemeldungen für Windows – per PowerShell statt per Klick.**

Setzt die lokalen Sicherheitsoptionen
*„Interaktive Anmeldung: Nachrichtentitel / Nachrichtentext für Benutzer, die sich anmelden möchten“*
sofort, einmalig zu einem Zeitfenster oder täglich wiederkehrend.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4?logo=windows&logoColor=white)
![Admin](https://img.shields.io/badge/Rechte-Administrator-critical)

</div>

---

## ✨ Features

| | |
|---|---|
| ⚡ **Sofort setzen oder entfernen** | Titel und Text mit einem Befehl aktivieren oder leeren |
| 🗓️ **Einmaliges Zeitfenster** | z. B. Wartungshinweis von Freitag 18:00 bis Samstag 06:00. Die geplanten Aufgaben räumen sich danach selbst auf |
| 🔁 **Täglich wiederkehrend** | z. B. jeden Abend 20:00–07:00, auch über Mitternacht |
| 🧩 **Platzhalter** | `{DATUM}`, `{ENDE}`, `{COMPUTER}` … werden beim Setzen automatisch ersetzt |
| 🛡️ **Läuft als SYSTEM** | über die Aufgabenplanung, unabhängig davon, ob jemand angemeldet ist |
| 📜 **Protokoll** | jede Änderung landet mit Zeitstempel im Log |
| 🇩🇪 **Deutsche Datumsformate** | `"24.10.2026 18:00"` funktioniert direkt |

---

## 🚀 Schnellstart

```powershell
# PowerShell als Administrator öffnen
Set-ExecutionPolicy -Scope Process Bypass

# Meldung sofort setzen
.\Set-LogonNotice.ps1 -Action Set -Title "Hinweis" -Text "Nur für autorisierte Benutzer."

# Prüfen
.\Set-LogonNotice.ps1 -Action Status
```

Die Meldung erscheint bei der nächsten Anmeldung (abmelden oder sperren genügt, sobald sich der nächste Benutzer anmeldet).

---

## 📖 Aktionen

| Aktion | Beschreibung | Pflichtparameter |
|---|---|---|
| `Set` | Meldung sofort setzen. Ohne `-Title` / `-Text` wird die gespeicherte Konfiguration verwendet | `-Title` und/oder `-Text`* |
| `Clear` | Meldung sofort entfernen | – |
| `Schedule` | Geplante Aufgaben zum Setzen ab `-Start` und Entfernen ab `-End` anlegen | `-Start`, `-Title` und/oder `-Text` |
| `Unschedule` | Geplante Aufgaben löschen und Meldung entfernen | – |
| `Status` | Aktuelle Werte, geplante Aufgaben und die letzten Log-Einträge anzeigen | – |

<sub>* nur wenn noch keine Konfiguration gespeichert ist</sub>

### Parameter

| Parameter | Typ | Beschreibung |
|---|---|---|
| `-Action` | `Set` · `Clear` · `Schedule` · `Unschedule` · `Status` | Auszuführende Aktion |
| `-Title` | String | Nachrichtentitel |
| `-Text` | String | Nachrichtentext (Zeilenumbruch mit `\n`) |
| `-Start` | String | Startzeitpunkt, z. B. `"24.10.2026 18:00"` oder `"20:00"` |
| `-End` | String | Endzeitpunkt (optional; ohne Angabe bleibt die Meldung bestehen) |
| `-Daily` | Switch | Zeitfenster täglich wiederholen |

---

## 💡 Beispiele

### Wartungsfenster (einmalig)

```powershell
.\Set-LogonNotice.ps1 -Action Schedule `
    -Start "24.10.2026 18:00" -End "25.10.2026 06:00" `
    -Title "Wartungsarbeiten" `
    -Text "Wartung von {START} bis {ENDE}.\nBitte speichern Sie Ihre Arbeit."
```

### Außerhalb der Arbeitszeit (täglich)

```powershell
.\Set-LogonNotice.ps1 -Action Schedule -Daily `
    -Start "20:00" -End "07:00" `
    -Title "Außerhalb der Arbeitszeit" `
    -Text "Anmeldungen zwischen {STARTZEIT} und {ENDZEIT} werden protokolliert."
```

### Dauerhafter Rechtshinweis ab einem Stichtag

```powershell
.\Set-LogonNotice.ps1 -Action Schedule -Start "01.11.2026 00:00" `
    -Title "Rechtlicher Hinweis" `
    -Text "Dieses System ({COMPUTER}) darf nur von autorisierten Personen genutzt werden."
```

### Alles zurücksetzen

```powershell
.\Set-LogonNotice.ps1 -Action Unschedule
```

---

## 🧩 Platzhalter

| Platzhalter | Ersetzt durch | Beispiel |
|---|---|---|
| `{DATUM}` | Datum zum Zeitpunkt des Setzens | `24.10.2026` |
| `{ZEIT}` | Uhrzeit zum Zeitpunkt des Setzens | `18:00` |
| `{COMPUTER}` | Computername | `PC-BUERO-01` |
| `{START}` / `{ENDE}` | Start / Ende mit Datum | `24.10.2026 18:00` |
| `{STARTZEIT}` / `{ENDZEIT}` | Start / Ende nur Uhrzeit | `18:00` |
| `\n` | Zeilenumbruch | |

---

## ⚙️ Funktionsweise

```text
 Schedule ──► C:\ProgramData\LogonNotice\
               ├─ Set-LogonNotice.ps1   (Kopie des Skripts)
               ├─ config.json           (Titel, Text, Zeiten)
               └─ LogonNotice.log       (Protokoll)

 Aufgabenplanung  \LogonNotice\
   ├─ LogonNotice-Set    ──► -Action Set    ──┐
   └─ LogonNotice-Clear  ──► -Action Clear  ──┤
                                              ▼
 HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
   ├─ legalnoticecaption   (Titel)
   └─ legalnoticetext      (Text)
```

- Die Aufgaben laufen als **SYSTEM** mit höchsten Rechten. Verpasste Termine (z. B. PC war aus) werden beim nächsten Start nachgeholt.
- Liegt die aktuelle Zeit beim Anlegen bereits im Zeitfenster, wird die Meldung **sofort** gesetzt.
- Bei einmaligen Zeitfenstern entfernt die Clear-Aufgabe nach dem Lauf **beide Aufgaben** automatisch.
- Der Ordner `C:\ProgramData\LogonNotice` ist nur für **Administratoren und SYSTEM** zugänglich.

---

## ⚠️ Hinweise

> [!IMPORTANT]
> Das Skript muss in einer **PowerShell mit Administratorrechten** ausgeführt werden.

> [!WARNING]
> In einer **Domäne** kann eine Gruppenrichtlinie dieselben Optionen setzen. Sie überschreibt die lokalen Werte beim nächsten `gpupdate`. Prüfen mit `gpresult /h report.html`.

> [!TIP]
> Die Datei ist als **UTF-8 mit BOM** gespeichert, damit Umlaute auch in Windows PowerShell 5.1 korrekt dargestellt werden. Beim Bearbeiten diese Kodierung beibehalten.

---

## 🧪 Fehlersuche

| Problem | Lösung |
|---|---|
| *„Die Datei kann nicht geladen werden …“* | `Set-ExecutionPolicy -Scope Process Bypass` oder Datei entsperren: `Unblock-File .\Set-LogonNotice.ps1` |
| Meldung erscheint nicht | `-Action Status` prüfen; Domänen-GPO kontrollieren; neu anmelden |
| Aufgabe läuft nicht | Aufgabenplanung → `\LogonNotice\` → Verlauf; Ergebnis im Status (`0` = OK) |
| Ungültige Zeitangabe | Format `dd.MM.yyyy HH:mm` oder `HH:mm` verwenden |

Protokoll: `C:\ProgramData\LogonNotice\LogonNotice.log`

---

<div align="center">
<sub>Ausgelegt für Windows PowerShell 5.1 und PowerShell 7 · Keine externen Abhängigkeiten</sub>
</div>
