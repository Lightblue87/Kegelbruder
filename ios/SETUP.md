# Kegel Brüder iOS App – Setup

## Xcode-Projekt erstellen

1. Xcode öffnen → **File → New → Project**
2. **iOS → App** wählen
3. Einstellungen:
   - Product Name: `KegelBrueder`
   - Bundle Identifier: `de.kegelbrueder.app` (oder eigene Domain)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Minimum Deployment: **iOS 17.0**
4. Ordner wählen: `Kegelbruder/ios/`

## Dateien einbinden

Nach dem Erstellen des Projekts:

1. Im Xcode-Projekt-Navigator: alle Standard-Dateien löschen (ContentView.swift, Assets.xcassets behalten)
2. Rechtsklick auf den Projektordner → **Add Files to "KegelBrueder"**
3. Alle Ordner aus `ios/KegelBrueder/` hinzufügen:
   - `App/`
   - `Models/`
   - `Data/`
   - `ViewModels/`
   - `Views/`
4. **Sicherstellen**: "Copy items if needed" **DEAKTIVIEREN** (Add as reference)

## Info.plist Einstellungen

Folgende Keys in Info.plist hinzufügen:

```xml
<!-- Für Files App / OneDrive Zugriff -->
<key>UISupportsDocumentBrowser</key>
<false/>

<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>

<key>UIFileSharingEnabled</key>
<true/>
```

## OneDrive Ordner einrichten

**Auf dem Windows-PC:**
1. OneDrive installieren
2. Ordner erstellen: `OneDrive/Kegelbruder/`
3. Python-App Dateipfad anpassen (in config.py):
   ```python
   import os
   DATA_DIR = os.path.expanduser("~/OneDrive/Kegelbruder/")
   DATA_FILE = os.path.join(DATA_DIR, "kegel_brueder.json")
   # ... etc.
   ```

**Auf dem iPad/iPhone:**
1. OneDrive App aus dem App Store installieren
2. Mit demselben Microsoft-Konto anmelden
3. Kegel Brüder App öffnen
4. "Ordner auswählen" → In OneDrive navigieren → `Kegelbruder` Ordner wählen

## iPad-Optimierung

Die App ist für **iPad Split View** optimiert:
- Linke Seite: Navigation (Spielmenü, Verwaltung)
- Rechte Seite: Detail-Ansicht (Spielstand, Kassenverwaltung, etc.)

Auf dem **iPhone** läuft die App als normale Navigation-App.

## Mindestanforderungen

- iOS 17.0+
- iPad (empfohlen) oder iPhone
- OneDrive App (für Sync mit Windows-PC)
