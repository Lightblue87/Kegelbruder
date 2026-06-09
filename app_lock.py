"""
app_lock.py – Exklusiver Zugriffsschutz via app_lock-Tabelle (SQLite)

Automatischer Reset täglich um 01:00 Uhr.
"""

import logging
import platform
import socket
from datetime import datetime, time as dt_time

from database import get_connection

RESET_UHRZEIT = dt_time(1, 0)


def _lock_ist_abgelaufen(seit_str: str) -> bool:
    try:
        seit = datetime.fromisoformat(seit_str)
        jetzt = datetime.now()
        from datetime import timedelta
        reset_heute = datetime.combine(jetzt.date(), RESET_UHRZEIT)
        letzter_reset = reset_heute if jetzt >= reset_heute else datetime.combine(
            (jetzt - timedelta(days=1)).date(), RESET_UHRZEIT
        )
        return seit < letzter_reset
    except Exception:
        return True


def lock_lesen() -> dict | None:
    try:
        conn = get_connection()
        row = conn.execute("SELECT geraet, seit, plattform FROM app_lock WHERE id = 1").fetchone()
        if row is None:
            return None
        return {"gerät": row["geraet"], "seit": row["seit"], "plattform": row["plattform"]}
    except Exception:
        return None


def lock_setzen():
    inhalt = {
        "gerät":     platform.node() or socket.gethostname() or "Unbekannt",
        "seit":      datetime.now().isoformat(),
        "plattform": platform.system(),
    }
    try:
        conn = get_connection()
        conn.execute(
            "INSERT OR REPLACE INTO app_lock (id, geraet, seit, plattform) VALUES (1, ?, ?, ?)",
            (inhalt["gerät"], inhalt["seit"], inhalt["plattform"]),
        )
        conn.commit()
        logging.info(f"Lock gesetzt: {inhalt}")
    except Exception as e:
        logging.error(f"Lock konnte nicht gesetzt werden: {e}")


def lock_freigeben():
    try:
        conn = get_connection()
        conn.execute("DELETE FROM app_lock WHERE id = 1")
        conn.commit()
        logging.info("Lock freigegeben.")
    except Exception as e:
        logging.error(f"Lock konnte nicht gelöscht werden: {e}")


def lock_pruefen_und_setzen(root) -> bool:
    from tkinter import messagebox

    lock = lock_lesen()

    if lock is None:
        lock_setzen()
        return True

    if _lock_ist_abgelaufen(lock.get("seit", "")):
        logging.info("Veralteter Lock gefunden – wird übernommen.")
        lock_setzen()
        return True

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
