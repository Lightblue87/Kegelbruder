import json
import logging
import os
import shutil
import threading

from config import (
    DATA_FILE,
    AKTUELLES_SPIEL,
    HISTORIE_FILE,
    MITGLIEDER_DATEI,
)
from storage import AtomicFileWriter


# =============================================================================
# Datenzugriff
# =============================================================================
class DatenHandler:
    _file_lock = threading.Lock()  # FIX #7: Thread-Sicherheit

    @staticmethod
    def _safe_read_json(path, default):
        """Sichere JSON-Lesevorgänge mit Fehlerbehandlung"""
        with DatenHandler._file_lock:
            if os.path.exists(path):
                try:
                    with open(path, "r") as f:
                        data = json.load(f)
                        # FIX: Validierung
                        if data is None:
                            raise ValueError("Datei ist leer")
                        return data
                except (json.JSONDecodeError, ValueError, IOError) as e:
                    logging.error(f"Fehler beim Lesen {path}: {e} – Backup erstellen")
                    # FIX #7: Backup vor Overwrite
                    if os.path.exists(path):
                        shutil.copy2(path, f"{path}.corrupted")

            # Mit atomarem Schreiben speichern
            success = AtomicFileWriter.atomic_write(path, default, backup=False)
            if not success:
                logging.error(f"Konnte {path} nicht initialisieren")
            return default

    @staticmethod
    def laden_mitglieder():
        return DatenHandler._safe_read_json(MITGLIEDER_DATEI, {"players": {}})

    @staticmethod
    def speichern_mitglieder(players):
        try:
            data = {"players": players}
            AtomicFileWriter.atomic_write(MITGLIEDER_DATEI, data)
        except Exception as e:
            logging.error(f"Speichern Mitglieder fehlgeschlagen: {e}")

    @staticmethod
    def laden():
        return DatenHandler._safe_read_json(DATA_FILE, {"players": {}, "kasse": {}})

    @staticmethod
    def laden_spiel():
        return DatenHandler._safe_read_json(
            AKTUELLES_SPIEL,
            {"players": {}, "runde": 0, "abgerechnet": False}
        )

    @staticmethod
    def speichern_spiel(data):
        try:
            AtomicFileWriter.atomic_write(AKTUELLES_SPIEL, data)
        except Exception as e:
            logging.error(f"Speichern aktuelles Spiel fehlgeschlagen: {e}")

    @staticmethod
    def archivieren_spiel(spieldaten):
        historie = DatenHandler._safe_read_json(HISTORIE_FILE, [])
        if "spieler_reihenfolge" not in spieldaten and "players" in spieldaten:
            spieldaten["spieler_reihenfolge"] = list(spieldaten["players"].keys())
        historie.append(spieldaten)

        # FIX: Begrenzen auf letzte 100 Spiele (Performance)
        if len(historie) > 100:
            historie = historie[-100:]
            logging.warning("Historie auf letzte 100 Spiele begrenzt")

        try:
            AtomicFileWriter.atomic_write(HISTORIE_FILE, historie)
        except Exception as e:
            logging.error(f"Speichern Historie fehlgeschlagen: {e}")
