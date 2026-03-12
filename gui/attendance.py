"""
gui/attendance.py – Anwesenheitserfassung, Spielreihenfolge, Spielstart

Enthält den kompletten UI-Ablauf:
  show_anwesenheit  →  verarbeite_anwesenheit  →  sort_players_window  →  start_game

Der Ablauf wird als Klasse organisiert, damit die kurzlebigen Widget-Referenzen
(anwesenheit_vars, bezahlung_vars, …) sauber lokal bleiben und nicht auf
KegelBruederApp landen.
"""

import logging
import tkinter as tk
from tkinter import messagebox, ttk

from data_handler import DatenHandler


class AttendanceFlow:
    """Verwaltet den kompletten Ablauf: Anwesenheit → Reihenfolge → Spielstart."""

    def __init__(self, app):
        self.app = app
        # Kurzlebiger UI-Zustand – nur während dieses Flows gültig
        self.anwesenheit_vars: dict = {}
        self.bezahlung_vars: dict = {}
        self.gastspieler_vars: list = []
        self.anwesenheit_window: tk.Toplevel = None
        self.gastspieler_dropdown: ttk.Combobox = None
        self._guest_row_idx: int = 0
        self.reihenfolge_listbox: tk.Listbox = None

    def open(self):
        """Öffnet das Anwesenheitsfenster und startet den Flow."""
        mit = DatenHandler.laden_mitglieder().get("players", {})
        if not mit:
            messagebox.showerror("Fehler", "Keine Spieler vorhanden!")
            return

        # Schulden vor der Session merken (für Rollback in abort_game)
        try:
            self.app._pre_session_schulden = {
                name: float(pdata.get("offene_zahlung", 0.0))
                for name, pdata in mit.items()
            }
        except Exception:
            self.app._pre_session_schulden = {}

        win = tk.Toplevel(self.app.root)
        win.title("Anwesenheit")
        win.grab_set()
        self.anwesenheit_window = win

        content = ttk.Frame(win)
        content.pack(side="top", fill="both", expand=True, padx=12, pady=(10, 6))

        bottom = ttk.Frame(win)
        bottom.pack(side="bottom", fill="x", padx=12, pady=(0, 10))

        ttk.Label(content, text="Spieler",           font=("Arial", 10, "bold")).grid(row=0, column=0, padx=6, pady=2, sticky="w")
        ttk.Label(content, text="Typ",               font=("Arial", 10, "bold")).grid(row=0, column=1, padx=6, pady=2, sticky="w")
        ttk.Label(content, text="Anwesend",          font=("Arial", 10, "bold")).grid(row=0, column=2, padx=6, pady=2, sticky="w")
        ttk.Label(content, text="Heute gezahlt (€)", font=("Arial", 10, "bold")).grid(row=0, column=3, padx=6, pady=2, sticky="w")
        ttk.Label(content, text="Offen",             font=("Arial", 10, "bold")).grid(row=0, column=4, padx=6, pady=2, sticky="w")

        startgeld = float(self.app.kasse.kasse.get("Startgeld", 5.0))

        def _update_offen_label(name):
            pdata = DatenHandler.laden_mitglieder().get("players", {}).get(name, {})
            offen_bisher = float(pdata.get("offene_zahlung", 0.0))
            add = startgeld if self.anwesenheit_vars[name].get() else 0.0
            gesamt = round(offen_bisher + add, 2)
            lbl = self.bezahlung_vars[name][1]
            lbl.config(text=f"{gesamt:.2f} €", foreground=("red" if gesamt > 0 else "green"))

        row = 1
        for name, pdata in sorted(mit.items()):
            if pdata.get("typ", "Stamm") != "Stamm":
                continue

            ttk.Label(content, text=name).grid(row=row, column=0, padx=6, pady=2, sticky="w")
            ttk.Label(content, text="Stamm").grid(row=row, column=1, padx=6, pady=2, sticky="w")

            var_anw = tk.BooleanVar(value=False)

            def _mk_toggle(n=name):
                return lambda: (
                    self.bezahlung_vars[n][2].config(
                        state=("normal" if self.anwesenheit_vars[n].get() else "disabled")
                    ),
                    _update_offen_label(n)
                )

            chk = ttk.Checkbutton(content, variable=var_anw, command=_mk_toggle(name))
            chk.grid(row=row, column=2, padx=6, pady=2, sticky="w")
            self.anwesenheit_vars[name] = var_anw

            betrag_var = tk.StringVar(value="0,00")
            ent = ttk.Entry(content, textvariable=betrag_var, width=10, state="disabled")
            ent.grid(row=row, column=3, padx=6, pady=2, sticky="w")

            offen_lbl = ttk.Label(content, text="0,00 €", foreground="green")
            offen_lbl.grid(row=row, column=4, padx=6, pady=2, sticky="w")

            self.bezahlung_vars[name] = (betrag_var, offen_lbl, ent)
            _update_offen_label(name)
            row += 1

        ttk.Separator(content).grid(row=row, column=0, columnspan=5, sticky="ew", pady=(8, 6))
        row += 1

        ttk.Label(content, text="Gast hinzufügen:").grid(row=row, column=0, padx=6, pady=2, sticky="w")
        alle_gaeste = sorted([n for n, d in mit.items() if d.get("typ") == "Gast"])
        self.gastspieler_dropdown = ttk.Combobox(content, values=alle_gaeste, state="readonly")
        self.gastspieler_dropdown.grid(row=row, column=1, columnspan=2, padx=6, pady=2, sticky="ew")

        guests_frame = ttk.Frame(content)
        guests_frame.grid(row=row + 1, column=0, columnspan=5, sticky="ew")
        guests_frame.grid_columnconfigure(0, weight=1)
        self._guest_row_idx = 0

        def add_guest():
            gast = self.gastspieler_dropdown.get()
            if not gast or gast in self.gastspieler_vars:
                return
            self.gastspieler_vars.append(gast)

            r = self._guest_row_idx
            ttk.Label(guests_frame, text=gast).grid(row=r, column=0, padx=6, pady=2, sticky="w")
            ttk.Label(guests_frame, text="Gast").grid(row=r, column=1, padx=6, pady=2, sticky="w")
            ttk.Label(guests_frame, text="").grid(row=r, column=2, padx=6, pady=2, sticky="w")

            g_var = tk.StringVar(value="0,00")
            g_ent = ttk.Entry(guests_frame, textvariable=g_var, width=10)
            g_ent.grid(row=r, column=3, padx=6, pady=2, sticky="w")

            offen_txt = ttk.Label(guests_frame, text=f"{startgeld:.2f} €", foreground="red")
            offen_txt.grid(row=r, column=4, padx=6, pady=2, sticky="w")

            self.bezahlung_vars[gast] = (g_var, offen_txt, g_ent)
            self._guest_row_idx += 1
            self.gastspieler_dropdown.set("")

        ttk.Button(content, text="Hinzufügen", command=add_guest).grid(row=row, column=3, padx=6, pady=2, sticky="w")
        row += 2

        ttk.Separator(content).grid(row=row, column=0, columnspan=5, sticky="ew", pady=(8, 0))

        ttk.Button(
            bottom, text="Abbrechen",
            command=lambda: (win.destroy(), self.app.abort_game(silent=True))
        ).pack(side="right", padx=(0, 8))
        ttk.Button(bottom, text="Weiter", command=self._verarbeite_anwesenheit).pack(side="right")

    # ------------------------------------------------------------------
    def _verarbeite_anwesenheit(self):
        """Verarbeitet die Anwesenheitseingaben und öffnet die Reihenfolge-Ansicht."""
        aktive = [p for p, v in self.anwesenheit_vars.items() if v.get()] + self.gastspieler_vars
        if not aktive:
            messagebox.showerror("Fehler", "Es muss mindestens ein Spieler anwesend sein!")
            return

        gespeicherte = DatenHandler.laden_mitglieder().get("players", {})
        for p, d in gespeicherte.items():
            if p not in self.app.players:
                self.app.players[p] = d

        startgeld = float(self.app.kasse.kasse["Startgeld"])
        strafe    = float(self.app.kasse.kasse["Strafe Stamm"])

        for p in self.app.players:
            self.app.players[p].setdefault("offene_zahlung", 0.0)
            if p in aktive:
                self.app.players[p]["offene_zahlung"] += startgeld
            elif self.app.players[p]["typ"] == "Stamm":
                self.app.players[p]["offene_zahlung"] += strafe

        for p, (betrag_var, schulden_label, entry) in self.bezahlung_vars.items():
            try:
                bezahlt = float(betrag_var.get().replace(",", "."))
            except ValueError:
                bezahlt = 0.0
            offen = float(self.app.players.get(p, {}).get("offene_zahlung", 0.0))
            if bezahlt > 0:
                if bezahlt >= offen:
                    self.app._session_einzahlung(bezahlt, f"Zahlung von {p}", spieler=p)
                    schulden_label.config(text="Offen: 0,00 €", foreground="green")
                    self.app.players[p]["offene_zahlung"] = 0.0
                else:
                    rest = offen - bezahlt
                    self.app._session_einzahlung(bezahlt, f"Teilzahlung von {p}", spieler=p)
                    self.app.players[p]["offene_zahlung"] = rest
                    schulden_label.config(text=f"Offen: {rest:.2f} €", foreground="red")

        DatenHandler.speichern_mitglieder(self.app.players)
        self._sort_players_window(self.anwesenheit_window)

    def _sort_players_window(self, anwesenheit_window):
        """Öffnet das Fenster zur Spielreihenfolge."""
        active_players = [p for p, v in self.anwesenheit_vars.items() if v.get()] + self.gastspieler_vars
        if not active_players:
            messagebox.showerror("Fehler", "Es muss mindestens ein Spieler anwesend sein!")
            return

        anwesenheit_window.destroy()

        win = tk.Toplevel(self.app.root)
        win.title("Spielreihenfolge festlegen")
        win.geometry("400x450")

        ttk.Label(win, text="Spielerreihenfolge:", font=("Arial", 12, "bold")).pack(pady=10)
        self.reihenfolge_listbox = tk.Listbox(win, height=10)
        self.reihenfolge_listbox.pack(pady=5, padx=20, fill="both", expand=True)

        letzte = self.app.lade_letzte_reihenfolge()
        lst = sorted(active_players, key=lambda x: (letzte.index(x) if x in letzte else 99))
        for p in lst:
            self.reihenfolge_listbox.insert(tk.END, p)

        bf = ttk.Frame(win)
        bf.pack(pady=5)
        ttk.Button(bf, text="▲ Hoch",   command=lambda: self._move_player(-1)).pack(side="left", padx=5)
        ttk.Button(bf, text="▼ Runter", command=lambda: self._move_player(1)).pack(side="left", padx=5)
        ttk.Button(win, text="Spiel starten", command=lambda: self._start_game(win)).pack(pady=10)

    def _move_player(self, direction):
        sel = self.reihenfolge_listbox.curselection()
        if not sel:
            return
        idx     = sel[0]
        new_idx = idx + direction
        if 0 <= new_idx < self.reihenfolge_listbox.size():
            p = self.reihenfolge_listbox.get(idx)
            self.reihenfolge_listbox.delete(idx)
            self.reihenfolge_listbox.insert(new_idx, p)
            self.reihenfolge_listbox.select_set(new_idx)

    def _start_game(self, window):
        """Startet das Spiel mit den gewählten Spielern in der gewählten Reihenfolge."""
        aktive = list(self.reihenfolge_listbox.get(0, tk.END))
        if not aktive:
            messagebox.showerror("Fehler", "Es muss mindestens ein Spieler anwesend sein!")
            return

        self.app.tiebreak_extras = {}

        # FIX #4: Dateninkonsistenz beim Spielstart – immer aus Quelle laden
        mit = DatenHandler.laden_mitglieder().get("players", {})
        self.app.players = {}
        for p in aktive:
            original = mit.get(p, {})
            self.app.players[p] = {
                "typ":            original.get("typ", "Stamm"),
                "punkte":         [0, 0, 0, 0],
                "offene_zahlung": float(original.get("offene_zahlung", 0.0)),
                "position":       aktive.index(p) + 1,
            }

        self.app.player_order = aktive[:]
        DatenHandler.speichern_spiel({"players": self.app.players, "runde": 1, "abgerechnet": False})
        self.app.runde = 1

        self.app.create_punkteingabe()
        self.app.kasse.aktualisiere_kasse(self.app.players)
        self.app.save_results()
        window.destroy()
