#!/usr/bin/env python3
"""
Kegel Brüder App – Einstiegspunkt

Startet Tkinter, richtet Styles ein und erzeugt die Hauptanwendung.
Keine fachliche Geschäftslogik in dieser Datei.
"""

import logging
import tkinter as tk

from styles import setup_styles
from app import KegelBruederApp

logging.basicConfig(
    filename="kegel_brueder.log",
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

if __name__ == "__main__":
    root = tk.Tk()
    setup_styles()
    app = KegelBruederApp(root)
    root.mainloop()
