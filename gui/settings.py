"""
gui/settings.py – Kosten-Einstellungsfenster + Datenpfad-Konfiguration
"""

import os
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from config import get_daten_verzeichnis, speichere_daten_verzeichnis


class KostenEinstellungenWindow:
    """Öffnet den Einstellungs-Dialog mit Kosten und Datenpfad."""

    _DEFAULTS = {
        "Startgeld":    5.0,
        "Pumpe":        0.5,
        "Neuner":       1.0,
        "Kranz":        2.0,
        "Strafe Stamm": 7.5,
        "Bahngebühr":  30.0,
    }
    _FIELDS = ["Startgeld", "Pumpe", "Neuner", "Kranz", "Strafe Stamm", "Bahngebühr"]

    def __init__(self, parent: tk.Misc, kasse):
        self.kasse  = kasse
        self.parent = parent

        win = tk.Toplevel(parent)
        win.title("Einstellungen")
        win.resizable(False, False)
        self.win = win

        notebook = ttk.Notebook(win)
        notebook.pack(fill="both", expand=True, padx=10, pady=10)

        # ── Tab 1: Kosten ─────────────────────────────────────────────────────
        kosten_frame = ttk.Frame(notebook, padding=10)
        notebook.add(kosten_frame, text="Kosten")
        self._build_kosten_tab(kosten_frame)

        # ── Tab 2: Datenpfad ──────────────────────────────────────────────────
        pfad_frame = ttk.Frame(notebook, padding=10)
        notebook.add(pfad_frame, text="Datenspeicherort")
        self._build_pfad_tab(pfad_frame)

    # ── Kosten-Tab ────────────────────────────────────────────────────────────

    def _build_kosten_tab(self, frame: ttk.Frame):
        ttk.Label(
            frame, text="Kosten anpassen:", font=("Arial", 11, "bold")
        ).grid(row=0, column=0, columnspan=2, pady=(0, 10), sticky="w")

        vars_ = {}
        row = 1
        for key in self._FIELDS:
            if key not in self.kasse.kasse:
                self.kasse.kasse[key] = self._DEFAULTS[key]
            ttk.Label(frame, text=key).grid(row=row, column=0, padx=(0, 10), pady=4, sticky="w")
            v = tk.StringVar(value=f"{self.kasse.kasse[key]:.2f}".replace(".", ","))
            ttk.Entry(frame, textvariable=v, width=10).grid(row=row, column=1, pady=4, sticky="w")
            vars_[key] = v
            row += 1

        ttk.Label(frame, text="€", foreground="gray").grid(row=1, column=2, rowspan=len(self._FIELDS), padx=4)

        def save_kosten():
            for key, var in vars_.items():
                try:
                    value = float(var.get().replace(",", "."))
                    if value < 0:
                        messagebox.showerror("Fehler", f"Betrag für {key} kann nicht negativ sein.", parent=self.win)
                        return
                    self.kasse.anpassen_gebuehren(key, value)
                except ValueError:
                    messagebox.showerror("Fehler", f"Ungültiger Betrag für {key}.", parent=self.win)
                    return
            messagebox.showinfo("Gespeichert", "Kosten erfolgreich aktualisiert.", parent=self.win)

        ttk.Button(frame, text="Kosten speichern", command=save_kosten).grid(
            row=row, column=0, columnspan=2, pady=(14, 0), sticky="ew"
        )

    # ── Datenpfad-Tab ─────────────────────────────────────────────────────────

    def _build_pfad_tab(self, frame: ttk.Frame):
        ttk.Label(
            frame,
            text="Ordner für alle Spielstandsdaten:",
            font=("Arial", 11, "bold")
        ).grid(row=0, column=0, columnspan=3, pady=(0, 6), sticky="w")

        ttk.Label(
            frame,
            text="Wähle z. B. deinen OneDrive-Ordner, damit die Daten\n"
                 "automatisch mit anderen Geräten synchronisiert werden.",
            foreground="gray"
        ).grid(row=1, column=0, columnspan=3, pady=(0, 12), sticky="w")

        # Aktueller Pfad (Anzeige + Entry zum direkten Eintippen)
        ttk.Label(frame, text="Aktueller Ordner:").grid(row=2, column=0, sticky="w", pady=4)

        self._pfad_var = tk.StringVar(value=get_daten_verzeichnis())
        pfad_entry = ttk.Entry(frame, textvariable=self._pfad_var, width=48)
        pfad_entry.grid(row=2, column=1, padx=(6, 4), pady=4, sticky="ew")

        ttk.Button(frame, text="Durchsuchen…", command=self._ordner_waehlen).grid(
            row=2, column=2, pady=4
        )

        frame.columnconfigure(1, weight=1)

        # Hinweis: Neustart erforderlich
        hinweis = ttk.Label(
            frame,
            text="⚠  Der neue Ordner wird erst nach einem Neustart der App vollständig aktiv.\n"
                 "   Bestehende Daten müssen manuell in den neuen Ordner kopiert werden.",
            foreground="#b05000",
            wraplength=420,
            justify="left"
        )
        hinweis.grid(row=3, column=0, columnspan=3, pady=(10, 0), sticky="w")

        ttk.Button(
            frame, text="Ordner übernehmen", command=self._pfad_speichern
        ).grid(row=4, column=0, columnspan=3, pady=(16, 0), sticky="ew")

    def _ordner_waehlen(self):
        aktuell = self._pfad_var.get()
        start = aktuell if os.path.isdir(aktuell) else os.path.expanduser("~")
        gewählt = filedialog.askdirectory(
            parent=self.win,
            title="Datenordner auswählen",
            initialdir=start,
            mustexist=True
        )
        if gewählt:
            self._pfad_var.set(gewählt)

    def _pfad_speichern(self):
        neuer_pfad = self._pfad_var.get().strip()
        if not neuer_pfad:
            messagebox.showerror("Fehler", "Bitte einen Ordner auswählen.", parent=self.win)
            return
        if not os.path.isdir(neuer_pfad):
            messagebox.showerror(
                "Fehler",
                f"Der Ordner existiert nicht:\n{neuer_pfad}",
                parent=self.win
            )
            return

        speichere_daten_verzeichnis(neuer_pfad)

        # DB-Verbindung zurücksetzen damit beim nächsten Zugriff die neue DB geöffnet wird
        import database
        if database._connection is not None:
            try:
                database._connection.close()
            except Exception:
                pass
            database._connection = None

        from database import init_db
        init_db()

        messagebox.showinfo(
            "Gespeichert",
            f"Datenordner gespeichert:\n{neuer_pfad}\n\n"
            "Die App verwendet ab sofort diesen Ordner.\n"
            "Bestehende Daten müssen ggf. manuell kopiert werden.",
            parent=self.win
        )
