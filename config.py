# -------------------- Zentrale Konfiguration / Dateinamen --------------------

import json
import os

# Die App-Einstellungen (inkl. Datenpfad) liegen immer neben der App selbst
_APP_DIR = os.path.dirname(os.path.abspath(__file__))
_APP_SETTINGS_FILE = os.path.join(_APP_DIR, "app_settings.json")

_DATEI_NAMEN = {
    "data":      "kegel_brueder.json",
    "kasse":     "kasse.json",
    "spiel":     "aktuelles_spiel.json",
    "historie":  "historie.json",
    "mitglieder":"mitglieder.json",
    "lock":      "kegelbruder.lock",
}


def _lade_daten_verzeichnis() -> str:
    """Liest das konfigurierte Datenverzeichnis aus app_settings.json."""
    try:
        if os.path.exists(_APP_SETTINGS_FILE):
            with open(_APP_SETTINGS_FILE, "r", encoding="utf-8") as f:
                settings = json.load(f)
                verzeichnis = settings.get("daten_verzeichnis", "")
                if verzeichnis and os.path.isdir(verzeichnis):
                    return verzeichnis
    except Exception:
        pass
    return _APP_DIR  # Fallback: App-Verzeichnis


def speichere_daten_verzeichnis(verzeichnis: str):
    """Speichert das neue Datenverzeichnis in app_settings.json."""
    try:
        settings = {}
        if os.path.exists(_APP_SETTINGS_FILE):
            with open(_APP_SETTINGS_FILE, "r", encoding="utf-8") as f:
                settings = json.load(f)
        settings["daten_verzeichnis"] = verzeichnis
        with open(_APP_SETTINGS_FILE, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2, ensure_ascii=False)
    except Exception as e:
        import logging
        logging.error(f"Datenverzeichnis konnte nicht gespeichert werden: {e}")


def get_data_path(schluessel: str) -> str:
    """Gibt den vollständigen Pfad zur Datendatei zurück (immer aktuell)."""
    verzeichnis = _lade_daten_verzeichnis()
    dateiname = _DATEI_NAMEN.get(schluessel, schluessel)
    return os.path.join(verzeichnis, dateiname)


def get_daten_verzeichnis() -> str:
    """Gibt das aktuell konfigurierte Datenverzeichnis zurück."""
    return _lade_daten_verzeichnis()


# Rückwärtskompatible Konstanten (werden beim Import einmalig gesetzt –
# für Code der noch direkt importiert, aber get_data_path() ist bevorzugt)
DATA_FILE       = get_data_path("data")
DATA_FILE_KASSE = get_data_path("kasse")
AKTUELLES_SPIEL = get_data_path("spiel")
HISTORIE_FILE   = get_data_path("historie")
MITGLIEDER_DATEI= get_data_path("mitglieder")
LOCK_FILE_PATH  = get_data_path("lock")
