"""
app_lock.py – Exklusiver Zugriffsschutz via Lock-Datei (OneDrive-kompatibel)

Die Lock-Datei liegt im selben Ordner wie die JSON-Daten.
Automatischer Reset täglich um 01:00 Uhr (falls App abstürzt oder nicht sauber beendet wurde).
"""

import json
import logging
import os
import platform
import socket
from datetime import datetime, time as dt_time

from config import get_data_path

LOCK_FILE = "kegelbruder.lock"  # Dateiname; Pfad immer über get_data_path("lock")
RESET_UHRZEIT = dt_time(1, 0)   # 01:00 Uhr


def _lock_ist_abgelaufen(seit_str: str) -> bool:
    """Lock gilt als veraltet wenn er vor dem letzten 01:00-Uhr-Schnitt gesetzt wurde."""
    try:
        seit = datetime.fromisoformat(seit_str)
        jetzt = datetime.now()

        # Letzter 01:00-Uhr-Zeitpunkt (heute oder gestern)
        reset_heute = datetime.combine(jetzt.date(), RESET_UHRZEIT)
        letzter_reset = reset_heute if jetzt >= reset_heute else datetime.combine(
            jetzt.date().replace(day=jetzt.day - 1), RESET_UHRZEIT
        )

        return seit < letzter_reset
    except Exception:
        return True  # Im Zweifel: abgelaufen


def lock_lesen() -> dict | None:
    """Gibt den Lock-Inhalt zurück, oder None wenn kein Lock existiert."""
    pfad = get_data_path("lock")
    if not os.path.exists(pfad):
        return None
    try:
        with open(pfad, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def lock_setzen():
    """Erstellt die Lock-Datei für dieses Gerät."""
    inhalt = {
        "gerät": platform.node() or socket.gethostname() or "Unbekannt",
        "seit": datetime.now().isoformat(),
        "plattform": platform.system(),
    }
    try:
        with open(get_data_path("lock"), "w", encoding="utf-8") as f:
            json.dump(inhalt, f, indent=2, ensure_ascii=False)
        logging.info(f"Lock gesetzt: {inhalt}")
    except Exception as e:
        logging.error(f"Lock konnte nicht gesetzt werden: {e}")


def lock_freigeben():
    """Löscht die Lock-Datei beim sauberen Beenden."""
    try:
        pfad = get_data_path("lock")
        if os.path.exists(pfad):
            os.remove(pfad)
            logging.info("Lock freigegeben.")
    except Exception as e:
        logging.error(f"Lock konnte nicht gelöscht werden: {e}")


def lock_pruefen_und_setzen(root) -> bool:
    """
    Prüft ob ein anderes Gerät die App bereits offen hat.
    Gibt True zurück wenn die App starten darf, False wenn sie blockiert wird.
    root: Tkinter-Root (für Dialoge)
    """
    from tkinter import messagebox

    lock = lock_lesen()

    if lock is None:
        lock_setzen()
        return True

    # Abgelaufener Lock (vor 01:00 Uhr des aktuellen Tages gesetzt)
    if _lock_ist_abgelaufen(lock.get("seit", "")):
        logging.info("Veralteter Lock gefunden – wird übernommen.")
        lock_setzen()
        return True

    # Aktiver Lock von einem anderen Gerät
    gerät = lock.get("gerät", "Unbekannt")
    seit_raw = lock.get("seit", "")
    try:
        seit = datetime.fromisoformat(seit_raw).strftime("%d.%m.%Y %H:%M Uhr")
    except Exception:
        seit = seit_raw

    antwort = messagebox.askyesno(
        "App bereits geöffnet",
        f"Die Kegel Brüder App ist bereits geöffnet auf:\n\n"
        f"  Gerät:  {gerät}\n"
        f"  Seit:   {seit}\n\n"
        f"Möchtest du den Zugriff trotzdem übernehmen?\n"
        f"(Das andere Gerät verliert dann die Kontrolle.)",
        icon="warning"
    )

    if antwort:
        logging.warning(f"Lock von '{gerät}' manuell übernommen.")
        lock_setzen()
        return True

    logging.info("App-Start vom Benutzer abgebrochen (Lock aktiv).")
    return False
