import json
import logging
import os
import shutil
import tempfile


# =================== FIX #7: Atomare Dateischreibvorgänge ===================
class AtomicFileWriter:
    """Sichere Dateischreibvorgänge mit Backup"""

    @staticmethod
    def atomic_write(file_path, data, backup=True):
        """Schreibt Datei atomar (entweder komplett oder gar nicht)"""
        try:
            # Backup erstellen wenn Datei existiert
            if backup and os.path.exists(file_path):
                backup_path = f"{file_path}.backup"
                shutil.copy2(file_path, backup_path)
                logging.info(f"Backup erstellt: {backup_path}")

            # In temporärer Datei schreiben
            with tempfile.NamedTemporaryFile(
                mode='w', delete=False, suffix='.json',
                dir=os.path.dirname(file_path) or '.'
            ) as f:
                json.dump(data, f, indent=4)
                temp_path = f.name

            # Atomar ersetzen
            if os.path.exists(file_path):
                os.replace(file_path, f"{file_path}.old")
            os.replace(temp_path, file_path)

            # Alte Datei löschen
            if os.path.exists(f"{file_path}.old"):
                os.remove(f"{file_path}.old")

            return True
        except Exception as e:
            logging.error(f"Fehler beim atomaren Schreiben von {file_path}: {e}")
            # Versuch, von Backup zu restaurieren
            backup_path = f"{file_path}.backup"
            if os.path.exists(backup_path):
                try:
                    shutil.copy2(backup_path, file_path)
                    logging.warning(f"Von Backup restauriert: {file_path}")
                except Exception as e2:
                    logging.error(f"Fehler beim Restore: {e2}")
            return False
