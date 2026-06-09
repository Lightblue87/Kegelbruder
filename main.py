#!/usr/bin/env python3
"""
Kegel Brüder App – Einstiegspunkt

Startet Tkinter, richtet Styles ein und erzeugt die Hauptanwendung.
Keine fachliche Geschäftslogik in dieser Datei.
"""

import logging
import tkinter as tk

from app_lock import lock_freigeben, lock_pruefen_und_setzen
from database import init_db
from styles import setup_styles
from app import KegelBruederApp

logging.basicConfig(
    filename="kegel_brueder.log",
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

if __name__ == "__main__":
    init_db()
    root = tk.Tk()
    setup_styles()

    if not lock_pruefen_und_setzen(root):
        root.destroy()
    else:
        app = KegelBruederApp(root)

        _original_on_close = app.on_close
        def _on_close_mit_lock():
            lock_freigeben()
            _original_on_close()
        app.on_close = _on_close_mit_lock
        root.protocol("WM_DELETE_WINDOW", app.on_close)

        root.mainloop()
