"""
gui/game_session.py – Punkteingabe-/Spielfeld-Widget-Bereich

Kapselt:
  - Aufbau des Punkteingabe-Grids         (rebuild)
  - Sperren aller Eingabefelder            (sperre)
  - Entsperren aller Eingabefelder         (entsperre)

Snapshot/Restore, Tab-/Fokus-Logik und Summenberechnung bleiben
ausdrücklich in app.py, weil sie stark mit dem App-Zustand verflochten sind.

Widget-Referenzen (punkte_entries, zusatzfelder, arrow_buttons, round_entries,
punkte_frame) werden nach rebuild() auf das app-Objekt zurückgeschrieben,
damit der bestehende Snapshot/Tab-Code in app.py unverändert weiterläuft.
"""

import logging
import tkinter as tk
from tkinter import messagebox, ttk


class GameSessionFrame:
    """Verwaltet den Punkteingabe-Widget-Bereich des Hauptfensters."""

    def __init__(self, app):
        self.app = app
        self.punkte_frame:   ttk.Frame = None
        self.punkte_entries: dict      = {}
        self.zusatzfelder:   dict      = {}
        self.arrow_buttons:  dict      = {}
        self.round_entries:  list      = [[] for _ in range(4)]

    # ------------------------------------------------------------------
    def rebuild(self):
        """Zerstört den alten Frame und baut den Punkteingabe-Bereich neu auf.

        Schreibt punkte_frame, punkte_entries, zusatzfelder, arrow_buttons und
        round_entries danach auf self.app zurück, so dass Snapshot/Restore und
        Tab-Logik (in app.py) unverändert weiterarbeiten können.
        """
        app = self.app

        # Alten Frame aufräumen
        if self.punkte_frame is not None:
            for entry_list in self.punkte_entries.values():
                for entry in entry_list:
                    if hasattr(entry, "unbind"):
                        try:
                            entry.unbind("<KeyRelease>")
                            entry.unbind("<FocusOut>")
                            entry.unbind("<FocusIn>")
                        except Exception:
                            pass
            try:
                self.punkte_frame.destroy()
            except Exception:
                pass

        self.punkte_entries = {}
        self.zusatzfelder   = {}
        self.arrow_buttons  = {}
        self.round_entries  = [[] for _ in range(4)]

        self.punkte_frame = ttk.Frame(app.root)
        self.punkte_frame.grid(row=1, column=0, columnspan=9, padx=10, pady=5, sticky="ew")

        for i in range(9):
            self.punkte_frame.columnconfigure(i, weight=1)

        ttk.Label(
            self.punkte_frame, text="Punkteingabe für jede Runde:", font=("Arial", 12, "bold")
        ).grid(row=0, column=0, columnspan=9, pady=5, sticky="ew")

        headers = ["Spieler", "Pumpen", "Neuner", "Kranz",
                   "Runde 1", "Runde 2", "Runde 3", "Runde 4", "Summe"]
        for i, header in enumerate(headers):
            ttk.Label(self.punkte_frame, text=header, font=("Arial", 10, "bold")
                      ).grid(row=1, column=i, padx=5, pady=5, sticky="ew")

        if not getattr(app, "player_order", None):
            app.player_order = list(app.players.keys())

        row = 2
        for player in app.player_order:
            ttk.Label(self.punkte_frame, text=player
                      ).grid(row=row, column=0, padx=10, pady=5, sticky="w")

            self.punkte_entries[player] = []
            self.zusatzfelder[player]   = {}
            self.arrow_buttons[player]  = {}

            for i, feld in enumerate(["Pumpen", "Neuner", "Kranz"]):
                frame = ttk.Frame(self.punkte_frame)
                frame.grid(row=row, column=i + 1, padx=5, pady=5, sticky="ew")
                var = tk.IntVar(value=0)

                def _trace_save(*_, _app=app, _player=player, _feld=feld):
                    try:
                        _app.save_runtime_snapshot()
                    except Exception as exc:
                        logging.error(f"Fehler beim Speichern ({_player}/{_feld}): {exc}")
                try:
                    var.trace_add("write", _trace_save)
                except Exception:
                    pass

                entry = ttk.Entry(frame, width=5, justify="center",
                                  textvariable=var, state="readonly")
                entry.pack(side="left")

                def inc(v=var): v.set(v.get() + 1)
                def dec(v=var): v.set(max(0, v.get() - 1))

                up = ttk.Button(frame, text="▲", width=2, command=lambda v=var: inc(v))
                dn = ttk.Button(frame, text="▼", width=2, command=lambda v=var: dec(v))
                dn.pack(side="right")
                up.pack(side="right")
                self.zusatzfelder[player][feld]  = var
                self.arrow_buttons[player][feld] = (up, dn)

            for r in range(4):
                e = ttk.Entry(self.punkte_frame, width=10, justify="center")
                e.grid(row=row, column=r + 4, padx=5, pady=5, sticky="ew")

                def select_all_if_zero(event, entry=e):
                    if entry.get().strip() == "0":
                        entry.selection_range(0, tk.END)

                e.bind("<FocusIn>", select_all_if_zero)
                e.bind("<KeyRelease>", lambda evt, _app=app:
                       getattr(_app, "save_runtime_snapshot", lambda: None)())
                e.bind("<FocusOut>", lambda evt, p=player, _app=app: (
                    _app.update_sum(p),
                    getattr(_app, "save_runtime_snapshot", lambda: None)()
                ))
                self.punkte_entries[player].append(e)
                self.round_entries[r].append(e)

            sum_label = ttk.Label(self.punkte_frame, text="0", font=("Arial", 10, "bold"))
            sum_label.grid(row=row, column=8, padx=10, pady=5, sticky="ew")
            self.punkte_entries[player].append(sum_label)
            row += 1

        # Sync widget-refs back to app so snapshot/tab code works unchanged
        app.punkte_frame   = self.punkte_frame
        app.punkte_entries = self.punkte_entries
        app.zusatzfelder   = self.zusatzfelder
        app.arrow_buttons  = self.arrow_buttons
        app.round_entries  = self.round_entries

    # ------------------------------------------------------------------
    def sperre(self, zeige_popup: bool = True):
        """Sperrt alle Punkteingabe-Felder."""
        app = self.app

        if hasattr(app, "abrechnung_button"):
            app.abrechnung_button.config(state="disabled")

        for player in list(self.zusatzfelder):
            for feld in ("Pumpen", "Neuner", "Kranz"):
                try:
                    self.zusatzfelder[player][feld].set(0)
                    for mode, cbname in self.zusatzfelder[player][feld].trace_info():
                        self.zusatzfelder[player][feld].trace_remove(mode, cbname)
                except Exception:
                    pass

        for player in list(self.arrow_buttons):
            for _, (up_btn, down_btn) in self.arrow_buttons[player].items():
                if up_btn and up_btn.winfo_exists():
                    up_btn.config(state="disabled")
                if down_btn and down_btn.winfo_exists():
                    down_btn.config(state="disabled")

        for _, entry_list in self.punkte_entries.items():
            for entry in entry_list[:-1]:
                try:
                    entry.config(state="disabled")
                except Exception:
                    pass

        if zeige_popup:
            messagebox.showinfo(
                "Spiel gesperrt",
                "Alle Felder gesperrt. Starte ein neues Spiel, um fortzufahren."
            )

    # ------------------------------------------------------------------
    def entsperre(self):
        """Entsperrt alle Punkteingabe-Felder."""
        app = self.app

        if hasattr(app, "abrechnung_button") and app.abrechnung_button:
            try:
                app.abrechnung_button.config(state="normal")
            except Exception:
                pass

        for _, entry_list in self.punkte_entries.items():
            for entry in entry_list[:-1]:
                try:
                    entry.config(state="normal")
                except Exception:
                    pass

        for _, buttons_for_player in self.arrow_buttons.items():
            for _, btn_pair in buttons_for_player.items():
                try:
                    up_btn, down_btn = btn_pair
                except Exception:
                    continue
                if up_btn and up_btn.winfo_exists():
                    try:
                        up_btn.config(state="normal")
                    except Exception:
                        pass
                if down_btn and down_btn.winfo_exists():
                    try:
                        down_btn.config(state="normal")
                    except Exception:
                        pass

        for player in getattr(app, "players", {}):
            if player not in self.zusatzfelder:
                continue
            for feld in ("Pumpen", "Neuner", "Kranz"):
                if feld not in self.zusatzfelder[player]:
                    logging.warning(
                        f"zusatzfelder[{player!r}][{feld!r}] fehlt nach rebuild – wird neu angelegt"
                    )
                    try:
                        self.zusatzfelder[player][feld] = tk.IntVar(value=0)
                    except Exception:
                        pass
