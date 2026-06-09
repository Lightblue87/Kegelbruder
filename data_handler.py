import json
import logging
import os
import shutil
import threading

from config import get_data_path
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
                            raise ValueError("Datei enthält ungültige Daten (null)")
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
        return DatenHandler._safe_read_json(get_data_path("mitglieder"), {"players": {}})

    @staticmethod
    def speichern_mitglieder(players):
        try:
            data = {"players": players}
            AtomicFileWriter.atomic_write(get_data_path("mitglieder"), data)
        except Exception as e:
            logging.error(f"Speichern Mitglieder fehlgeschlagen: {e}")

    @staticmethod
    def laden():
        return DatenHandler._safe_read_json(get_data_path("data"), {"players": {}, "kasse": {}})

    @staticmethod
    def laden_spiel():
        return DatenHandler._safe_read_json(
            get_data_path("spiel"),
            {"players": {}, "runde": 0, "abgerechnet": False}
        )

    @staticmethod
    def speichern_spiel(data):
        try:
            AtomicFileWriter.atomic_write(get_data_path("spiel"), data)
        except Exception as e:
            logging.error(f"Speichern aktuelles Spiel fehlgeschlagen: {e}")

    @staticmethod
    def reduziere_ausstehende_zahlung(player: str, betrag: float) -> bool:
        """Reduziert die offene Zahlung eines Spielers in der Mitgliederdatei.

        Gehört zur Persistenzschicht (hier), nicht zur Kassen-Fachlogik.
        Gibt True zurück wenn erfolgreich, False bei Fehler.
        """
        try:
            data = DatenHandler.laden_mitglieder()
            if player in data["players"]:
                schuld = data["players"][player].get("offene_zahlung", 0.0)
                data["players"][player]["offene_zahlung"] = max(0.0, float(schuld) - float(betrag))
                DatenHandler.speichern_mitglieder(data["players"])
            return True
        except Exception as e:
            logging.error(f"Reduzieren offene Zahlung fehlgeschlagen ({player}): {e}")
            return False

    @staticmethod
    def archivieren_spiel(spieldaten):
        historie = DatenHandler._safe_read_json(get_data_path("historie"), [])
        if "spieler_reihenfolge" not in spieldaten and "players" in spieldaten:
            spieldaten["spieler_reihenfolge"] = list(spieldaten["players"].keys())
        historie.append(spieldaten)

        # FIX: Begrenzen auf letzte 100 Spiele (Performance)
        if len(historie) > 100:
            historie = historie[-100:]
            logging.warning("Historie auf letzte 100 Spiele begrenzt")

        try:
            AtomicFileWriter.atomic_write(get_data_path("historie"), historie)
        except Exception as e:
            logging.error(f"Speichern Historie fehlgeschlagen: {e}")
