"""
gui/game_session.py – Punkteingabe-/Spielfeld-Widget-Bereich

Kapselt:
  - Aufbau des Punkteingabe-Grids         (rebuild)
  - Sperren aller Eingabefelder            (sperre)
  - Entsperren aller Eingabefelder         (entsperre)
  - Snapshot speichern                     (save_runtime_snapshot)
  - Snapshot laden und Felder befüllen     (load_runtime_snapshot)
  - Inhalt eines Snapshots prüfen          (_snapshot_has_content)
  - Tab-Reihenfolge aufbauen               (build_tab_order)
  - Tab-/Shift-Tab-Navigation              (_on_tab_key / _on_shift_tab_key)

Summenberechnung (update_sum) bleibt ausdrücklich in app.py.

Widget-Referenzen (punkte_entries, zusatzfelder, arrow_buttons, round_entries,
punkte_frame) werden nach rebuild() auf das app-Objekt zurückgeschrieben,
damit bestehender Code in app.py unverändert weiterläuft.
"""

import logging
import tkinter as tk
from tkinter import messagebox, ttk

from data_handler import DatenHandler


class GameSessionFrame:
    """Verwaltet den Punkteingabe-Widget-Bereich des Hauptfensters."""

    def __init__(self, app):
        self.app = app
        self.punkte_frame:   ttk.Frame = None
        self.punkte_entries: dict      = {}
        self.zusatzfelder:   dict      = {}
        self.arrow_buttons:  dict      = {}
        self.round_entries:  list      = [[] for _ in range(4)]
        self.tab_order:      list      = []
        self.entry_index:    dict      = {}

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

    # ------------------------------------------------------------------
    def _snapshot_has_content(self, snap_players: dict) -> bool:
        """Gibt True zurück, wenn snap_players mindestens einen nicht-leeren Wert enthält."""
        for _, d in (snap_players or {}).items():
            punkte = d.get("punkte", [])
            if any(str(x).strip() not in ("", "0") for x in punkte):
                return True
            if d.get("pumpen", 0) or d.get("neuner", 0) or d.get("kranz", 0):
                return True
        return False

    # ------------------------------------------------------------------
    def save_runtime_snapshot(self):
        """Liest die aktuellen Widget-Werte aus und speichert sie als Spiel-Snapshot."""
        try:
            app          = self.app
            snap_players = {}
            mit          = DatenHandler.laden_mitglieder().get("players", {})

            for player, entry_list in self.punkte_entries.items():
                runden = []
                for e in entry_list[:-1]:
                    try:
                        val = e.get().strip()
                        runden.append(int(val) if val else 0)
                    except Exception:
                        runden.append(0)

                zf = self.zusatzfelder.get(player, {})
                pu_var = zf.get("Pumpen")
                nn_var = zf.get("Neuner")
                kr_var = zf.get("Kranz")
                pu = int(pu_var.get()) if pu_var is not None else 0
                nn = int(nn_var.get()) if nn_var is not None else 0
                kr = int(kr_var.get()) if kr_var is not None else 0

                pdata = mit.get(player, {})
                typ   = pdata.get("typ",   app.players.get(player, {}).get("typ",   "Stamm"))
                offen = float(pdata.get("offene_zahlung",
                              app.players.get(player, {}).get("offene_zahlung", 0.0)))

                snap_players[player] = {
                    "typ":            typ,
                    "punkte":         runden[:4] if len(runden) >= 4 else [0, 0, 0, 0],
                    "offene_zahlung": offen,
                    "pumpen":         pu,
                    "neuner":         nn,
                    "kranz":          kr,
                }

            if snap_players and self._snapshot_has_content(snap_players):
                DatenHandler.speichern_spiel({
                    "players": snap_players, "runde": 1, "abgerechnet": False
                })
            else:
                DatenHandler.speichern_spiel({"players": {}, "runde": 0, "abgerechnet": False})
        except Exception as e:
            logging.error(f"Fehler beim Snapshot-Speichern: {e}")

    # ------------------------------------------------------------------
    def load_runtime_snapshot(self):
        """Lädt den gespeicherten Spiel-Snapshot und befüllt die Widgets."""
        try:
            app  = self.app
            snap = DatenHandler.laden_spiel()
            if not snap or snap.get("abgerechnet"):
                return
            snap_players = snap.get("players", {})
            if not snap_players:
                return

            mit          = DatenHandler.laden_mitglieder().get("players", {})
            app.players  = {}
            for name, d in snap_players.items():
                base = mit.get(name, {})
                app.players[name] = {
                    "typ":            base.get("typ", d.get("typ", "Stamm")),
                    "punkte":         d.get("punkte", [0, 0, 0, 0]),
                    "offene_zahlung": float(base.get("offene_zahlung",
                                           d.get("offene_zahlung", 0.0))),
                }

            app.create_punkteingabe()

            for name, d in snap_players.items():
                punkte = d.get("punkte", [0, 0, 0, 0])[:4]
                if name in self.punkte_entries:
                    for i in range(4):
                        try:
                            self.punkte_entries[name][i].delete(0, tk.END)
                            self.punkte_entries[name][i].insert(0, str(punkte[i]))
                        except Exception:
                            pass
                    try:
                        self.punkte_entries[name][-1].config(text=str(sum(punkte)))
                    except Exception:
                        pass

                zf = self.zusatzfelder.get(name, {})
                for feld, key in (("Pumpen", "pumpen"), ("Neuner", "neuner"), ("Kranz", "kranz")):
                    var = zf.get(feld)
                    if var is not None:
                        try:
                            var.set(int(d.get(key, 0)))
                        except Exception:
                            pass

            self.save_runtime_snapshot()
        except Exception as e:
            logging.error(f"Fehler beim Snapshot-Laden: {e}")

    # ------------------------------------------------------------------
    def build_tab_order(self):
        """Baut die Tab-Reihenfolge für die Rundenfelder auf und registriert die Key-Bindings.

        Muss nach rebuild() aufgerufen werden, da die Widgets erst dann existieren.
        Bindings werden nur auf frisch erzeugten Widgets gesetzt; da rebuild() alle
        alten Widgets zerstört, entstehen keine doppelten Bindings.
        """
        app = self.app
        self.tab_order   = []
        self.entry_index = {}
        idx = 0
        for r in range(4):
            if r >= len(self.round_entries):
                break
            for p in range(len(app.player_order)):
                try:
                    w = self.round_entries[r][p]
                except IndexError:
                    continue
                if not w:
                    continue
                self.tab_order.append(w)
                self.entry_index[w] = idx
                w.bind("<Tab>",          self._on_tab_key)
                w.bind("<ISO_Left_Tab>", self._on_shift_tab_key)
                w.bind("<Shift-Tab>",    self._on_shift_tab_key)
                idx += 1

    # ------------------------------------------------------------------
    def _on_tab_key(self, event):
        if not self.tab_order:
            return
        i   = self.entry_index.get(event.widget, 0)
        nxt = (i + 1) % len(self.tab_order)
        self.tab_order[nxt].focus_set()
        return "break"

    # ------------------------------------------------------------------
    def _on_shift_tab_key(self, event):
        if not self.tab_order:
            return
        i   = self.entry_index.get(event.widget, 0)
        prv = (i - 1) % len(self.tab_order)
        self.tab_order[prv].focus_set()
        return "break"
