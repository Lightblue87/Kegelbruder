"""
gui/cash_management.py – Kassenverwaltungsfenster

Kapselt alle Widget-Referenzen des Kassenverwaltungsfensters.
app.py hält nur eine Referenz auf das laufende Fenster-Objekt und ruft
refresh_kassenstand / refresh_transaktionen / refresh_offene auf.
"""

import tkinter as tk
from tkinter import messagebox, ttk

from data_handler import DatenHandler


class CashManagementWindow:
    """Kassenverwaltungsfenster mit Kassenstand, offenen Zahlungen und Transaktionen."""

    def __init__(self, app):
        self.app = app
        # Widget-Referenzen – lokal in diesem Fenster, nicht mehr auf app
        self.win:              tk.Toplevel  = None
        self.kassenstand_label: ttk.Label  = None
        self.offene_txt:        tk.Text    = None
        self.spieler_var:       tk.StringVar = None
        self.spieler_drop:      ttk.Combobox = None
        self.betrag_entry:      ttk.Entry  = None
        self.spende_entry:      ttk.Entry  = None
        self.trans_widget:      tk.Text    = None
        self._build()

    # ------------------------------------------------------------------
    def _build(self):
        win = tk.Toplevel(self.app.root)
        self.win = win
        win.title("Kassenverwaltung")
        win.geometry("960x600")
        win.minsize(860, 520)

        for c in range(4):
            win.grid_columnconfigure(c, weight=1)
        win.grid_rowconfigure(2, weight=1)
        win.grid_rowconfigure(8, weight=1)

        ttk.Label(win, text="Kassenstand:", font=("Arial", 12, "bold")).grid(
            row=0, column=0, padx=10, pady=(10, 5), sticky="w"
        )
        self.kassenstand_label = ttk.Label(
            win, text=f"{self.app.kasse.get_kassenstand():.2f} €", font=("Arial", 12, "bold")
        )
        self.kassenstand_label.grid(row=0, column=1, columnspan=3, padx=10, pady=(10, 5), sticky="w")

        ttk.Label(win, text="Offene Zahlungen:", font=("Arial", 10, "bold")).grid(
            row=1, column=0, padx=10, pady=5, sticky="w"
        )

        offene_frame = ttk.Frame(win)
        offene_frame.grid(row=2, column=0, columnspan=4, padx=10, pady=5, sticky="nsew")
        offene_frame.grid_columnconfigure(0, weight=1)
        offene_frame.grid_rowconfigure(0, weight=1)

        self.offene_txt = tk.Text(offene_frame, wrap="none")
        self.offene_txt.grid(row=0, column=0, sticky="nsew")
        vsb_off = ttk.Scrollbar(offene_frame, orient="vertical", command=self.offene_txt.yview)
        vsb_off.grid(row=0, column=1, sticky="ns")
        hsb_off = ttk.Scrollbar(offene_frame, orient="horizontal", command=self.offene_txt.xview)
        hsb_off.grid(row=1, column=0, sticky="ew")
        self.offene_txt.configure(yscrollcommand=vsb_off.set, xscrollcommand=hsb_off.set)

        ttk.Label(win, text="Spieler:", font=("Arial", 10)).grid(row=4, column=0, padx=10, pady=(10, 5), sticky="w")
        self.spieler_var  = tk.StringVar()
        self.spieler_drop = ttk.Combobox(win, textvariable=self.spieler_var, state="readonly")
        self.spieler_drop.grid(row=4, column=1, padx=10, pady=(10, 5), sticky="ew")

        ttk.Label(win, text="Betrag:", font=("Arial", 10)).grid(row=4, column=2, padx=10, pady=(10, 5), sticky="w")
        self.betrag_entry = ttk.Entry(win)
        self.betrag_entry.grid(row=4, column=3, padx=10, pady=(10, 5), sticky="ew")

        ttk.Label(win, text="Spende:", font=("Arial", 10)).grid(row=5, column=2, padx=10, pady=5, sticky="w")
        self.spende_entry = ttk.Entry(win)
        self.spende_entry.grid(row=5, column=3, padx=10, pady=5, sticky="ew")

        btn_row = ttk.Frame(win)
        btn_row.grid(row=6, column=0, columnspan=4, padx=10, pady=10, sticky="w")
        ttk.Button(btn_row, text="Einzahlen", command=self._einzahlen).pack(side="left", padx=(0, 8))
        ttk.Button(btn_row, text="Auszahlen", command=self._auszahlen).pack(side="left")

        ttk.Label(win, text="Letzte Transaktionen:", font=("Arial", 10, "bold")).grid(
            row=7, column=0, padx=10, pady=(10, 5), sticky="w"
        )

        trans_frame = ttk.Frame(win)
        trans_frame.grid(row=8, column=0, columnspan=4, padx=10, pady=5, sticky="nsew")
        trans_frame.grid_columnconfigure(0, weight=1)
        trans_frame.grid_rowconfigure(0, weight=1)

        self.trans_widget = tk.Text(trans_frame, wrap="none", state=tk.DISABLED)
        self.trans_widget.grid(row=0, column=0, sticky="nsew")
        vsb_tx = ttk.Scrollbar(trans_frame, orient="vertical", command=self.trans_widget.yview)
        vsb_tx.grid(row=0, column=1, sticky="ns")
        hsb_tx = ttk.Scrollbar(trans_frame, orient="horizontal", command=self.trans_widget.xview)
        hsb_tx.grid(row=1, column=0, sticky="ew")
        self.trans_widget.configure(yscrollcommand=vsb_tx.set, xscrollcommand=hsb_tx.set)

        self.refresh_offene()
        self.refresh_transaktionen()

    # ------------------------------------------------------------------
    def _einzahlen(self):
        try:
            betrag = float((self.betrag_entry.get() or "0").replace(",", "."))
        except ValueError:
            messagebox.showerror("Fehler", "Bitte gültigen Betrag eingeben.")
            return
        try:
            spende = float((self.spende_entry.get() or "0").replace(",", "."))
        except ValueError:
            messagebox.showerror("Fehler", "Bitte gültige Spende eingeben.")
            return

        if betrag < 0 or spende < 0:
            messagebox.showerror("Fehler", "Beträge dürfen nicht negativ sein.")
            return

        spieler = (self.spieler_var.get() or "").strip() or None

        if betrag > 0:
            beschr = f"Zahlung von {spieler}" if spieler else "Zahlung (ohne Zuordnung)"
            self.app.kasse.einzahlung(betrag, beschr)
            # Offene Zahlung in Mitgliederdatei reduzieren (Persistenz liegt bei DatenHandler)
            if spieler:
                if not DatenHandler.reduziere_ausstehende_zahlung(spieler, betrag):
                    import logging
                    logging.warning(
                        f"Kasse aktualisiert, aber offene Zahlung für {spieler} konnte nicht "
                        "reduziert werden – bitte Mitgliederdatei prüfen."
                    )

        if spende > 0:
            beschr_s = f"Spende von {spieler}" if spieler else "Spende"
            self.app.kasse.einzahlung(spende, beschr_s)

        if betrag > 0 or spende > 0:
            self.refresh_kassenstand()
            self.refresh_transaktionen()
            self.refresh_offene()

    def _auszahlen(self):
        try:
            betrag = float((self.betrag_entry.get() or "0").replace(",", "."))
        except ValueError:
            messagebox.showerror("Fehler", "Bitte gültigen Betrag eingeben.")
            return

        if betrag < 0:
            messagebox.showerror("Fehler", "Betrag darf nicht negativ sein.")
            return
        if betrag <= 0:
            return
        if not self.app.kasse.auszahlung(betrag, "Manuelle Auszahlung"):
            messagebox.showerror("Fehler", "Nicht genügend Guthaben.")
            return

        self.refresh_kassenstand()
        self.refresh_transaktionen()

    # ------------------------------------------------------------------
    def refresh_kassenstand(self):
        """Aktualisiert den Kassenstand-Label (sicher auch wenn Fenster schon weg)."""
        try:
            if self.win.winfo_exists() and self.kassenstand_label.winfo_exists():
                self.kassenstand_label.config(text=f"{self.app.kasse.get_kassenstand():.2f} €")
        except tk.TclError:
            pass

    def refresh_transaktionen(self):
        """Aktualisiert die Transaktionsliste."""
        try:
            if not self.win.winfo_exists() or not self.trans_widget.winfo_exists():
                return
        except tk.TclError:
            return
        self.trans_widget.config(state=tk.NORMAL)
        self.trans_widget.delete("1.0", tk.END)
        for t in self.app.kasse.zeige_transaktionen(limit=200):
            self.trans_widget.insert(tk.END, t + "\n")
        self.trans_widget.config(state=tk.DISABLED)
        self.trans_widget.see(tk.END)

    def refresh_offene(self):
        """Aktualisiert Textfeld + Combobox der offenen Beträge (frisch aus Datei)."""
        try:
            if not self.win.winfo_exists():
                return
        except tk.TclError:
            return

        mit = DatenHandler.laden_mitglieder().get("players", {})
        offene = {
            p: float(d.get("offene_zahlung", 0.0))
            for p, d in mit.items()
            if d.get("typ") == "Stamm" and float(d.get("offene_zahlung", 0.0)) > 0
        }

        try:
            if self.offene_txt.winfo_exists():
                self.offene_txt.config(state=tk.NORMAL)
                self.offene_txt.delete("1.0", tk.END)
                for p, betrag in offene.items():
                    self.offene_txt.insert(tk.END, f"{p}: {betrag:.2f} €\n")
                self.offene_txt.config(state=tk.DISABLED)
        except tk.TclError:
            pass

        try:
            if self.spieler_drop.winfo_exists():
                self.spieler_drop["values"] = sorted(offene.keys())
        except tk.TclError:
            pass
