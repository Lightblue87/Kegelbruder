"""
gui/settings.py – Kosten-Einstellungsfenster

Kapselt:
  - KostenEinstellungenWindow: Toplevel-Dialog zum Anpassen von Startgeld,
    Pumpe, Neuner, Kranz, Strafe Stamm und Bahngebühr.

Die Klasse erhält nur das Parent-Fenster und das Kasse-Objekt.
Keine Abhängigkeit zu KegelBruederApp oder anderen app-lokalen Daten.
"""

import tkinter as tk
from tkinter import messagebox, ttk


class KostenEinstellungenWindow:
    """Öffnet den Kosten-Einstellungs-Dialog als Toplevel-Fenster."""

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
        self.kasse = kasse

        win = tk.Toplevel(parent)
        win.title("Kosten Einstellungen")
        self.win = win

        ttk.Label(
            win, text="Hier können die Kosten angepasst werden:", font=("Arial", 12, "bold")
        ).grid(row=0, column=0, columnspan=2, pady=10)

        vars_ = {}
        row   = 1
        for key in self._FIELDS:
            if key not in kasse.kasse:
                kasse.kasse[key] = self._DEFAULTS[key]
            ttk.Label(win, text=key).grid(row=row, column=0, padx=10, pady=5, sticky="w")
            v = tk.StringVar(value=f"{kasse.kasse[key]:.2f}".replace(".", ","))
            ttk.Entry(win, textvariable=v, width=10).grid(row=row, column=1, padx=10, pady=5, sticky="w")
            vars_[key] = v
            row += 1

        def save():
            for key, var in vars_.items():
                try:
                    value = float(var.get().replace(",", "."))
                    if value < 0:
                        messagebox.showerror("Fehler", f"Betrag für {key} kann nicht negativ sein.")
                        return
                    kasse.anpassen_gebuehren(key, value)
                except ValueError:
                    messagebox.showerror("Fehler", f"Ungültiger Betrag für {key}.")
                    return
            messagebox.showinfo("Gespeichert", "Kosten erfolgreich aktualisiert.")
            win.destroy()

        ttk.Button(win, text="Speichern", command=save).grid(row=row, column=0, columnspan=2, pady=10)
