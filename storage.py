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
        """Schreibt Datei atomar: vollständig in Temp-Datei schreiben, dann per os.replace() ersetzen.

        os.replace() ist auf POSIX-Systemen atomar (rename-Syscall) – es gibt kein Zeitfenster,
        in dem file_path nicht existiert. Das frühere Umbenennen file_path → .old war nicht atomar
        und erzeugte genau dieses Fenster.
        """
        temp_path = None
        try:
            # Optionales Backup der bestehenden Datei
            if backup and os.path.exists(file_path):
                backup_path = f"{file_path}.backup"
                shutil.copy2(file_path, backup_path)
                logging.info(f"Backup erstellt: {backup_path}")

            # Vollständig in Temp-Datei im selben Verzeichnis schreiben
            with tempfile.NamedTemporaryFile(
                mode='w', delete=False, suffix='.tmp',
                dir=os.path.dirname(os.path.abspath(file_path))
            ) as f:
                json.dump(data, f, indent=4)
                temp_path = f.name

            # Atomar ersetzen – kein Zeitfenster ohne file_path
            os.replace(temp_path, file_path)
            return True

        except Exception as e:
            logging.error(f"Fehler beim atomaren Schreiben von {file_path}: {e}")
            # Temp-Datei aufräumen, falls vorhanden
            if temp_path is not None and os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except Exception as e3:
                    logging.error(f"Temp-Datei konnte nicht gelöscht werden ({temp_path}): {e3}")
            # Versuch, von Backup zu restaurieren
            backup_path = f"{file_path}.backup"
            if os.path.exists(backup_path):
                try:
                    shutil.copy2(backup_path, file_path)
                    logging.warning(f"Von Backup restauriert: {file_path}")
                except Exception as e2:
                    logging.error(f"Fehler beim Restore: {e2}")
            return False
