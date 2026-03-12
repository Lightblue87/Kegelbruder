"""
app.py – KegelBruederApp (Hauptklasse / Koordinator)

Verantwortlichkeiten:
- Hauptfenster aufbauen (Menü, Toolbar, Punkteingabe-Grid)
- Spielstart, Abort, Snapshot, Restore
- Session-Buchungen (Rollback-fähig)
- Archivansicht
- Delegation der GUI-Bereiche an gui/ Module:
    gui/attendance.py   → AttendanceFlow
    gui/billing.py      → BillingWindow
    gui/cash_management → CashManagementWindow
"""

import logging
import tkinter as tk
from datetime import datetime
from tkinter import messagebox, ttk

from cashbox import Kasse
from config import DATA_FILE, AKTUELLES_SPIEL, HISTORIE_FILE
from data_handler import DatenHandler
from gui.attendance import AttendanceFlow
from gui.billing import BillingWindow
from gui.cash_management import CashManagementWindow
from storage import AtomicFileWriter


class KegelBruederApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Kegel Brüder")
        self.root.configure(bg="#f0f0f0")

        data         = DatenHandler.laden()
        self.players = data.get("players", {})
        self.kasse   = Kasse()

        self.runde           = 0
        self.player_order    = []
        self.tiebreak_extras: dict = {}

        self._session_tx:           list = []
        self._pre_session_schulden: dict = {}

        self.arrow_buttons:  dict = {}
        self.punkte_entries: dict = {}
        self.zusatzfelder:   dict = {}
        self.round_entries:  list = [[] for _ in range(4)]
        self.tab_order:      list = []
        self.entry_index:    dict = {}

        self._kassen_mgmt = None

        self.restore_players()
        self.kasse.aktualisiere_kasse(self.players)
        self.create_menu()
        self.create_widgets()
        self.create_punkteingabe()
        self.load_runtime_snapshot()

        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

    def create_menu(self):
        menu = tk.Menu(self.root)
        self.root.config(menu=menu)

        spiel_menu = tk.Menu(menu, tearoff=0)
        menu.add_cascade(label="Spiel", menu=spiel_menu)
        spiel_menu.add_command(label="Spiel abbrechen…", command=self.abort_game)

        einstellungen = tk.Menu(menu, tearoff=0)
        menu.add_cascade(label="Einstellungen", menu=einstellungen)
        einstellungen.add_command(label="Spieler verwalten",    command=self.manage_players)
        einstellungen.add_command(label="Kosten Einstellungen", command=self.open_kosten_einstellungen)

    def abort_game(self, silent: bool = False):
        if not silent:
            if not messagebox.askyesno(
                "Spiel abbrechen",
                "Möchtest du das laufende Spiel wirklich abbrechen?\n"
                "Alle heutigen Buchungen und Änderungen werden zurückgesetzt."
            ):
                return

        try:
            for kind, betrag, expected_text in reversed(self._session_tx):
                if not self.kasse.kasse["Transaktionen"]:
                    logging.warning("Transaktionsliste ist leer, Rollback stoppt")
                    break
                last = self.kasse.kasse["Transaktionen"][-1]
                if last != expected_text:
                    logging.warning(f"Transaktions-Mismatch: {last!r} != {expected_text!r}. Rollback stoppt.")
                    break
                if kind == "einzahlung":
                    self.kasse.kasse["Kassenstand"] = max(
                        0.0, float(self.kasse.kasse["Kassenstand"]) - float(betrag)
                    )
                elif kind == "auszahlung":
                    self.kasse.kasse["Kassenstand"] = float(self.kasse.kasse["Kassenstand"]) + float(betrag)
                self.kasse.kasse["Transaktionen"].pop()
            self.kasse.speichere_kasse()
            logging.info("Rollback erfolgreich")
        except Exception as e:
            logging.error(f"Fehler beim Rollback: {e}")
        finally:
            self._session_tx = []

        try:
            if self._pre_session_schulden:
                mit = DatenHandler.laden_mitglieder()
                for name, pdata in mit.get("players", {}).items():
                    if name in self._pre_session_schulden:
                        pdata["offene_zahlung"] = float(self._pre_session_schulden[name])
                DatenHandler.speichern_mitglieder(mit["players"])
        except Exception as e:
            logging.error(f"Fehler beim Restore der Schulden: {e}")
        finally:
            self._pre_session_schulden = {}

        try:
            self.sperre_spielfelder(zeige_popup=False)
        except Exception as e:
            logging.error(f"Fehler beim Sperren: {e}")

        self.tiebreak_extras = {}
        DatenHandler.speichern_spiel({"players": {}, "runde": 0, "abgerechnet": False})
        self.restore_players()
        self.create_punkteingabe()
        messagebox.showinfo(
            "Abgebrochen",
            "Das Spiel wurde abgebrochen. Alle Werte sind wieder auf dem Stand vor Spielbeginn."
        )

    def open_kosten_einstellungen(self):
        win = tk.Toplevel(self.root)
        win.title("Kosten Einstellungen")

        ttk.Label(win, text="Hier können die Kosten angepasst werden:", font=("Arial", 12, "bold")
                  ).grid(row=0, column=0, columnspan=2, pady=10)

        fields = ["Startgeld", "Pumpe", "Neuner", "Kranz", "Strafe Stamm", "Bahngebühr"]
        vars_  = {}
        row    = 1
        for key in fields:
            if key not in self.kasse.kasse:
                defaults = {
                    "Startgeld": 5.0, "Pumpe": 0.5, "Neuner": 1.0,
                    "Kranz": 2.0, "Strafe Stamm": 7.5, "Bahngebühr": 30.0
                }
                self.kasse.kasse[key] = defaults[key]
            ttk.Label(win, text=key).grid(row=row, column=0, padx=10, pady=5, sticky="w")
            v = tk.StringVar(value=f"{self.kasse.kasse[key]:.2f}".replace(".", ","))
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
                    self.kasse.anpassen_gebuehren(key, value)
                except ValueError:
                    messagebox.showerror("Fehler", f"Ungültiger Betrag für {key}.")
                    return
            messagebox.showinfo("Gespeichert", "Kosten erfolgreich aktualisiert.")
            win.destroy()

        ttk.Button(win, text="Speichern", command=save).grid(row=row, column=0, columnspan=2, pady=10)

    def create_widgets(self):
        ttk.Button(self.root, text="Neues Spiel",      command=self.start_new_game).grid(row=0, column=0, pady=5)
        ttk.Button(self.root, text="Kassenverwaltung", command=self.show_kassenverwaltung).grid(row=0, column=2, pady=5)

        self.abrechnung_button = ttk.Button(self.root, text="Abrechnung", command=self.show_abrechnung)
        self.abrechnung_button.grid(row=0, column=3, pady=5)

        ttk.Button(self.root, text="Archiv", command=self.show_archiv).grid(row=0, column=4, pady=5)

        gespeichertes_spiel = DatenHandler.laden_spiel()
        if gespeichertes_spiel.get("abgerechnet", False):
            self.abrechnung_button.config(state="disabled")

    def manage_players(self):
        win = tk.Toplevel(self.root)
        win.title("Spieler verwalten")

        self.player_listbox = tk.Listbox(win, height=10, width=50)
        self.player_listbox.grid(row=0, column=0, padx=10, pady=5, columnspan=3, sticky="ew")
        self.update_player_list()

        ttk.Label(win, text="Spielername:").grid(row=1, column=0, padx=10, pady=5, sticky="e")
        name_entry = ttk.Entry(win)
        name_entry.grid(row=1, column=1, padx=10, pady=5, sticky="w")

        ttk.Label(win, text="Typ:").grid(row=2, column=0, padx=10, pady=5, sticky="e")
        player_type = tk.StringVar(value="Stamm")
        rb_stamm = ttk.Radiobutton(win, text="Stamm", variable=player_type, value="Stamm")
        rb_gast  = ttk.Radiobutton(win, text="Gast",   variable=player_type, value="Gast")
        rb_stamm.grid(row=2, column=1, padx=10, pady=5, sticky="w")
        rb_gast.grid( row=2, column=2, padx=10, pady=5, sticky="w")

        ttk.Label(win, text="Offener Betrag (€):").grid(row=3, column=0, padx=10, pady=5, sticky="e")
        offener_betrag_var = tk.StringVar(value="0,00")
        offener_entry      = ttk.Entry(win, textvariable=offener_betrag_var, width=10)
        offener_entry.grid(row=3, column=1, padx=10, pady=5, sticky="w")

        def _toggle_offen(*_):
            if player_type.get() == "Stamm":
                offener_entry.config(state="normal")
            else:
                offener_entry.config(state="disabled")
                offener_betrag_var.set("0,00")
        player_type.trace_add("write", _toggle_offen)
        _toggle_offen()

        def _parse_money(s: str) -> float:
            s = (s or "0").strip().replace(",", ".")
            try:
                return max(0.0, float(s))
            except ValueError:
                return 0.0

        def add_player():
            name = name_entry.get().strip()
            typ  = player_type.get()
            if not name or typ not in ("Stamm", "Gast"):
                return
            mit = DatenHandler.laden_mitglieder()
            if name in mit["players"]:
                messagebox.showerror("Fehler", "Name existiert bereits.")
                return
            offene = _parse_money(offener_betrag_var.get()) if typ == "Stamm" else 0.0
            mit["players"][name] = {
                "typ": typ, "punkte": [0, 0, 0, 0], "offene_zahlung": float(offene)
            }
            DatenHandler.speichern_mitglieder(mit["players"])
            self.update_player_list()
            name_entry.delete(0, tk.END)
            offener_betrag_var.set("0,00")
            player_type.set("Stamm")

        def remove_player():
            sel      = self.player_listbox.get(tk.ACTIVE)
            selected = sel.split(" (")[0] if sel else ""
            if not selected:
                return
            mit = DatenHandler.laden_mitglieder()
            if selected in mit["players"]:
                if messagebox.askyesno("Spieler entfernen", f"{selected} wirklich löschen?"):
                    del mit["players"][selected]
                    DatenHandler.speichern_mitglieder(mit["players"])
                    self.update_player_list()

        def edit_player():
            sel      = self.player_listbox.get(tk.ACTIVE)
            selected = sel.split(" (")[0] if sel else ""
            if not selected:
                return
            mit = DatenHandler.laden_mitglieder()
            if selected not in mit["players"]:
                return

            pdata = mit["players"][selected]
            ew    = tk.Toplevel(self.root)
            ew.title("Spieler bearbeiten")

            ttk.Label(ew, text="Neuer Name:").grid(row=0, column=0, padx=10, pady=5, sticky="e")
            new_name_entry = ttk.Entry(ew)
            new_name_entry.grid(row=0, column=1, padx=10, pady=5, sticky="w")
            new_name_entry.insert(0, selected)

            ttk.Label(ew, text="Typ:").grid(row=1, column=0, padx=10, pady=5, sticky="e")
            typ_var = tk.StringVar(value=pdata.get("typ", "Stamm"))
            rb_s = ttk.Radiobutton(ew, text="Stamm", variable=typ_var, value="Stamm")
            rb_g = ttk.Radiobutton(ew, text="Gast",   variable=typ_var, value="Gast")
            rb_s.grid(row=1, column=1, padx=10, pady=5, sticky="w")
            rb_g.grid(row=1, column=2, padx=10, pady=5, sticky="w")

            ttk.Label(ew, text="Offener Betrag (€):").grid(row=2, column=0, padx=10, pady=5, sticky="e")
            offen_edit_var   = tk.StringVar(
                value=f"{float(pdata.get('offene_zahlung', 0.0)):.2f}".replace(".", ",")
            )
            offen_edit_entry = ttk.Entry(ew, textvariable=offen_edit_var, width=10)
            offen_edit_entry.grid(row=2, column=1, padx=10, pady=5, sticky="w")

            def _toggle_offen_edit(*_):
                if typ_var.get() == "Stamm":
                    offen_edit_entry.config(state="normal")
                else:
                    offen_edit_entry.config(state="disabled")
                    offen_edit_var.set("0,00")
            typ_var.trace_add("write", _toggle_offen_edit)
            _toggle_offen_edit()

            def save_edit():
                new_name = new_name_entry.get().strip()
                new_typ  = typ_var.get()
                if not new_name:
                    return
                if new_name != selected:
                    mit["players"][new_name] = mit["players"].pop(selected)
                mit["players"][new_name]["typ"] = new_typ
                if new_typ == "Stamm":
                    mit["players"][new_name]["offene_zahlung"] = _parse_money(offen_edit_var.get())
                else:
                    mit["players"][new_name]["offene_zahlung"] = 0.0
                DatenHandler.speichern_mitglieder(mit["players"])
                self.update_player_list()
                ew.destroy()

            ttk.Button(ew, text="Speichern", command=save_edit).grid(row=3, column=0, columnspan=3, pady=8)

        ttk.Button(win, text="Hinzufügen", command=add_player).grid(row=4, column=0, pady=8)
        ttk.Button(win, text="Entfernen",    command=remove_player).grid(row=4, column=1, pady=8)
        ttk.Button(win, text="Bearbeiten",   command=edit_player).grid(row=4, column=2, pady=8)

    def update_player_list(self):
        if not hasattr(self, "player_listbox"):
            return
        self.player_listbox.delete(0, tk.END)
        mit = DatenHandler.laden_mitglieder().get("players", {})
        for p, d in sorted(mit.items()):
            self.player_listbox.insert(tk.END, f"{p} ({d['typ']})")

    def create_punkteingabe(self):
        if hasattr(self, "punkte_frame"):
            for entry_list in self.punkte_entries.values():
                for entry in entry_list:
                    if hasattr(entry, "unbind"):
                        try:
                            entry.unbind("<KeyRelease>")
                            entry.unbind("<FocusOut>")
                            entry.unbind("<FocusIn>")
                        except Exception:
                            pass
            self.punkte_frame.destroy()

        self.punkte_frame = ttk.Frame(self.root)
        self.punkte_frame.grid(row=1, column=0, columnspan=9, padx=10, pady=5, sticky="ew")

        for i in range(9):
            self.punkte_frame.columnconfigure(i, weight=1)

        ttk.Label(self.punkte_frame, text="Punkteingabe für jede Runde:", font=("Arial", 12, "bold")
                  ).grid(row=0, column=0, columnspan=9, pady=5, sticky="ew")

        headers = ["Spieler", "Pumpen", "Neuner", "Kranz", "Runde 1", "Runde 2", "Runde 3", "Runde 4", "Summe"]
        for i, header in enumerate(headers):
            ttk.Label(self.punkte_frame, text=header, font=("Arial", 10, "bold")
                      ).grid(row=1, column=i, padx=5, pady=5, sticky="ew")

        self.punkte_entries = {}
        self.zusatzfelder   = {}
        self.arrow_buttons  = {}
        self.round_entries  = [[] for _ in range(4)]

        if not getattr(self, "player_order", None):
            self.player_order = list(self.players.keys())

        row = 2
        for player in self.player_order:
            ttk.Label(self.punkte_frame, text=player).grid(row=row, column=0, padx=10, pady=5, sticky="w")

            self.punkte_entries[player] = []
            self.zusatzfelder[player]   = {}
            self.arrow_buttons[player]  = {}

            for i, feld in enumerate(["Pumpen", "Neuner", "Kranz"]):
                frame = ttk.Frame(self.punkte_frame)
                frame.grid(row=row, column=i + 1, padx=5, pady=5, sticky="ew")
                var = tk.IntVar(value=0)

                def _trace_save(*_):
                    try:
                        self.save_runtime_snapshot()
                    except Exception as exc:
                        logging.error(f"Fehler beim Speichern: {exc}")
                try:
                    var.trace_add("write", _trace_save)
                except Exception:
                    pass

                entry = ttk.Entry(frame, width=5, justify="center", textvariable=var, state="readonly")
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

                e.bind("<FocusIn>",   select_all_if_zero)
                e.bind("<KeyRelease>", lambda evt, p=player:
                       getattr(self, "save_runtime_snapshot", lambda: None)())
                e.bind("<FocusOut>",  lambda evt, p=player: (
                    self.update_sum(p),
                    getattr(self, "save_runtime_snapshot", lambda: None)()
                ))
                self.punkte_entries[player].append(e)
                self.round_entries[r].append(e)

            sum_label = ttk.Label(self.punkte_frame, text="0", font=("Arial", 10, "bold"))
            sum_label.grid(row=row, column=8, padx=10, pady=5, sticky="ew")
            self.punkte_entries[player].append(sum_label)
            row += 1

        self._build_tab_order()

    def entsperre_spielfelder(self):
        if hasattr(self, "abrechnung_button") and self.abrechnung_button:
            try:
                self.abrechnung_button.config(state="normal")
            except Exception:
                pass

        for _, entry_list in getattr(self, "punkte_entries", {}).items():
            for entry in entry_list[:-1]:
                try:
                    entry.config(state="normal")
                except Exception:
                    pass

        for _, buttons_for_player in getattr(self, "arrow_buttons", {}).items():
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

        for player in getattr(self, "players", {}):
            if player not in getattr(self, "zusatzfelder", {}):
                continue
            for feld in ("Pumpen", "Neuner", "Kranz"):
                if feld not in self.zusatzfelder[player]:
                    try:
                        self.zusatzfelder[player][feld] = tk.IntVar(value=0)
                    except Exception:
                        pass

    def update_sum(self, player):
        try:
            punkte = [e.get().strip() for e in self.punkte_entries[player][:-1]]
            if all(p.isdigit() for p in punkte if p != "") and len([p for p in punkte if p != ""]) == 4:
                values = list(map(int, punkte))
                self.punkte_entries[player][-1].config(text=str(sum(values)))
                self.players[player]["punkte"] = values
                self.kasse.aktualisiere_kasse(self.players)
                self.save_results()
                self.save_runtime_snapshot()
        except Exception as e:
            logging.error(f"Fehler beim Update der Summe: {e}")

    def show_kassenverwaltung(self):
        if self._kassen_mgmt is not None:
            try:
                if self._kassen_mgmt.win.winfo_exists():
                    self._kassen_mgmt.win.lift()
                    return
            except Exception:
                pass
        self._kassen_mgmt = CashManagementWindow(self)

    def refresh_kassen_gui(self):
        try:
            if self._kassen_mgmt is not None and self._kassen_mgmt.win.winfo_exists():
                self._kassen_mgmt.refresh_kassenstand()
                self._kassen_mgmt.refresh_transaktionen()
                self._kassen_mgmt.refresh_offene()
        except Exception:
            pass

    def _session_reset(self):
        self._session_tx = []

    def _session_einzahlung(self, betrag: float, beschreibung: str, spieler=None):
        if betrag <= 0:
            return
        ok = self.kasse.einzahlung(betrag, beschreibung)
        if not ok:
            return
        if spieler:
            DatenHandler.reduziere_ausstehende_zahlung(spieler, betrag)
        datum      = datetime.now().strftime("%d.%m.%Y")
        entry_plus = f"{datum} | +{betrag:.2f}€: {beschreibung}"
        self._session_tx.append(("einzahlung", betrag, entry_plus))

    def _session_auszahlung(self, betrag: float, beschreibung: str):
        if betrag <= 0:
            return
        ok = self.kasse.auszahlung(betrag, beschreibung)
        if not ok:
            return
        datum       = datetime.now().strftime("%d.%m.%Y")
        entry_minus = f"{datum} | -{betrag:.2f}€: {beschreibung}"
        self._session_tx.append(("auszahlung", betrag, entry_minus))

    def start_new_game(self):
        gespeichertes_spiel = DatenHandler.laden_spiel()
        if gespeichertes_spiel.get("players"):
            messagebox.showinfo(
                "Info", "Ein Spiel läuft bereits. Bitte erst beenden oder Abrechnung durchführen."
            )
            return

        self.entsperre_spielfelder()

        mit = DatenHandler.laden_mitglieder().get("players", {})
        if not mit:
            messagebox.showinfo("Info", "Keine Spieler vorhanden. Füge zuerst Spieler hinzu.")
            return

        self.players      = dict(sorted(mit.items()))
        self.player_order = list(self.players.keys())
        self.create_punkteingabe()
        self.show_anwesenheit()

    def show_anwesenheit(self):
        flow = AttendanceFlow(self)
        flow.open()

    def show_abrechnung(self):
        billing = BillingWindow(self)
        billing.open()

    def sperre_spielfelder(self, zeige_popup: bool = True):
        if hasattr(self, "abrechnung_button"):
            self.abrechnung_button.config(state="disabled")

        for player in getattr(self, "players", {}):
            if player in getattr(self, "zusatzfelder", {}):
                for feld in ("Pumpen", "Neuner", "Kranz"):
                    try:
                        self.zusatzfelder[player][feld].set(0)
                        for trace_id in self.zusatzfelder[player][feld].trace_info():
                            self.zusatzfelder[player][feld].trace_remove("write", trace_id)
                    except Exception:
                        pass

        for player in getattr(self, "arrow_buttons", {}):
            for _, (up_btn, down_btn) in self.arrow_buttons[player].items():
                if up_btn and up_btn.winfo_exists():
                    up_btn.config(state="disabled")
                if down_btn and down_btn.winfo_exists():
                    down_btn.config(state="disabled")

        for _, entry_list in getattr(self, "punkte_entries", {}).items():
            for entry in entry_list[:-1]:
                try:
                    entry.config(state="disabled")
                except Exception:
                    pass

        if zeige_popup:
            messagebox.showinfo("Spiel gesperrt", "Alle Felder gesperrt. Starte ein neues Spiel, um fortzufahren.")

    def show_archiv(self):
        win = tk.Toplevel(self.root)
        win.title("Archiv")
        win.geometry("800x600")

        data = DatenHandler._safe_read_json(HISTORIE_FILE, [])
        try:
            data = sorted(data, key=lambda e: datetime.strptime(
                e.get("datum", "01.01.1900"), "%d.%m.%Y"), reverse=True)
        except Exception:
            pass

        overview = ttk.Treeview(win, columns=("Datum", "Spieler", "Transaktionen"), show="headings")
        overview.heading("Datum",         text="Datum")
        overview.heading("Spieler",       text="Spieleranzahl")
        overview.heading("Transaktionen", text="Transaktionen")
        overview.column("Datum",         width=110, anchor="center")
        overview.column("Spieler",       width=110, anchor="center")
        overview.column("Transaktionen", width=140, anchor="center")
        overview.pack(side="left", fill="y", padx=10, pady=10)

        for entry in data:
            datum       = entry.get("datum", "unbekannt")
            num_players = len(entry.get("players", {}))
            num_trans   = len(entry.get("transaktionen", []))
            overview.insert("", "end", values=(datum, num_players, num_trans))

        details = ttk.Frame(win)
        details.pack(side="top", fill="both", expand=True, padx=10, pady=10)

        ttk.Label(details, text="Finale Platzierung", font=("Arial", 10, "bold")).pack(pady=5)

        place_tree = ttk.Treeview(
            details,
            columns=("Platz", "Spieler", "Einzelpunkte", "Summe", "Pumpen"),
            show="headings", height=8
        )
        for col, txt, w, anchor in [
            ("Platz",        "Platz",        60,  "center"),
            ("Spieler",      "Spieler",      140, "w"),
            ("Einzelpunkte", "Einzelpunkte", 160, "w"),
            ("Summe",        "Punktesumme",  100, "center"),
            ("Pumpen",       "Pumpen",       80,  "center"),
        ]:
            place_tree.heading(col, text=txt)
            place_tree.column(col,  width=w, anchor=anchor)
        place_tree.tag_configure("topPump", background="lightblue")
        place_tree.pack(fill="x", padx=10, pady=5)

        ttk.Label(details, text="Transaktionen", font=("Arial", 10, "bold")).pack(pady=5)
        tx_tree = ttk.Treeview(details, columns=("Transaktion",), show="headings", height=8)
        tx_tree.heading("Transaktion", text="Transaktion")
        tx_tree.column("Transaktion",  anchor="w", width=500)
        tx_tree.pack(fill="both", expand=True, padx=10, pady=5)

        def on_select(event):
            sel = overview.selection()
            if not sel:
                return
            datum_sel = overview.item(sel[0], "values")[0]
            for entry in data:
                if entry.get("datum") == datum_sel:
                    for n in place_tree.get_children():
                        place_tree.delete(n)
                    for n in tx_tree.get_children():
                        tx_tree.delete(n)

                    order       = entry.get("spieler_reihenfolge") or list(entry.get("players", {}).keys())
                    pump_counts = {
                        p: entry.get("players", {}).get(p, {}).get("pumpen", 0)
                        for p in entry.get("players", {})
                    }
                    top_two = [p for p, _ in sorted(pump_counts.items(),
                                                     key=lambda x: x[1], reverse=True)[:2]]

                    for rank, player in enumerate(order, start=1):
                        pdata       = entry.get("players", {}).get(player, {})
                        punkte_list = pdata.get("punkte", [])
                        punkte_str  = ", ".join(map(str, punkte_list))
                        punkte_sum  = sum(punkte_list) if punkte_list else 0
                        pumps       = pdata.get("pumpen", 0)
                        tags        = ("topPump",) if player in top_two else ()
                        place_tree.insert("", "end",
                                          values=(rank, player, punkte_str, punkte_sum, pumps),
                                          tags=tags)

                    for t in entry.get("transaktionen", []):
                        tx_tree.insert("", "end", values=(t,))
                    break

        overview.bind("<<TreeviewSelect>>", on_select)
        ttk.Button(win, text="Schließen", command=win.destroy).pack(side="bottom", pady=10)

    def restore_players(self):
        mit        = DatenHandler.laden_mitglieder().get("players", {})
        spiel      = DatenHandler.laden_spiel()
        sp_players = spiel.get("players", {})
        for p, d in mit.items():
            d["punkte"] = (sp_players[p].get("punkte", [0, 0, 0, 0])
                           if p in sp_players else d.get("punkte", [0, 0, 0, 0]))
        self.players = mit
        DatenHandler.speichern_mitglieder(self.players)

    def lade_letzte_reihenfolge(self):
        try:
            historie = DatenHandler._safe_read_json(HISTORIE_FILE, [])
            if historie:
                def _to_dt(e):
                    try:
                        return datetime.strptime(e.get("datum", "01.01.1900"), "%d.%m.%Y")
                    except Exception:
                        return datetime.min
                last  = sorted(historie, key=_to_dt, reverse=True)[0]
                order = last.get("spieler_reihenfolge")
                if order and isinstance(order, list) and len(order) > 0:
                    return order
        except Exception:
            pass

        try:
            spiel = DatenHandler.laden_spiel()
            order = spiel.get("spieler_reihenfolge")
            if order and isinstance(order, list) and len(order) > 0:
                return order
            if spiel.get("players"):
                return list(spiel["players"].keys())
        except Exception:
            pass

        return sorted(list(self.players.keys()))

    def save_results(self):
        data = {"players": self.players, "kasse": self.kasse.kasse}
        try:
            AtomicFileWriter.atomic_write(DATA_FILE, data)
        except Exception as e:
            messagebox.showerror("Fehler", f"Speichern fehlgeschlagen: {e}")

    def on_close(self):
        mit = DatenHandler.laden_mitglieder().get("players", {})
        for p, d in self.players.items():
            mit[p] = {**mit.get(p, {}), **d}
        DatenHandler.speichern_mitglieder(mit)
        self.save_runtime_snapshot()
        self.save_results()
        self.root.destroy()

    def _snapshot_has_content(self, snap_players: dict) -> bool:
        for p, d in (snap_players or {}).items():
            punkte = d.get("punkte", [])
            if any(str(x).strip() not in ("", "0") for x in punkte):
                return True
            if d.get("pumpen", 0) or d.get("neuner", 0) or d.get("kranz", 0):
                return True
        return False

    def save_runtime_snapshot(self):
        try:
            snap_players = {}
            mit = DatenHandler.laden_mitglieder().get("players", {})

            for player, entry_list in self.punkte_entries.items():
                runden = []
                for e in entry_list[:-1]:
                    try:
                        val = e.get().strip()
                        runden.append(int(val) if val else 0)
                    except Exception:
                        runden.append(0)

                if player not in self.zusatzfelder:
                    pu = nn = kr = 0
                else:
                    pu = int(self.zusatzfelder[player].get("Pumpen", tk.IntVar(value=0)).get())
                    nn = int(self.zusatzfelder[player].get("Neuner", tk.IntVar(value=0)).get())
                    kr = int(self.zusatzfelder[player].get("Kranz",  tk.IntVar(value=0)).get())

                pdata = mit.get(player, {})
                typ   = pdata.get("typ",   self.players.get(player, {}).get("typ",   "Stamm"))
                offen = float(pdata.get("offene_zahlung",
                              self.players.get(player, {}).get("offene_zahlung", 0.0)))

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

    def load_runtime_snapshot(self):
        try:
            snap = DatenHandler.laden_spiel()
            if not snap or snap.get("abgerechnet"):
                return
            snap_players = snap.get("players", {})
            if not snap_players:
                return

            mit = DatenHandler.laden_mitglieder().get("players", {})
            self.players = {}
            for name, d in snap_players.items():
                base = mit.get(name, {})
                self.players[name] = {
                    "typ":            base.get("typ", d.get("typ", "Stamm")),
                    "punkte":         d.get("punkte", [0, 0, 0, 0]),
                    "offene_zahlung": float(base.get("offene_zahlung", d.get("offene_zahlung", 0.0))),
                }

            self.create_punkteingabe()

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

                if name in self.zusatzfelder:
                    try:
                        self.zusatzfelder[name]["Pumpen"].set(int(d.get("pumpen", 0)))
                    except Exception:
                        pass
                    try:
                        self.zusatzfelder[name]["Neuner"].set(int(d.get("neuner", 0)))
                    except Exception:
                        pass
                    try:
                        self.zusatzfelder[name]["Kranz"].set(int(d.get("kranz", 0)))
                    except Exception:
                        pass

            self.save_runtime_snapshot()
        except Exception as e:
            logging.error(f"Fehler beim Snapshot-Laden: {e}")

    def _build_tab_order(self):
        if not hasattr(self, "round_entries"):
            return
        self.tab_order   = []
        self.entry_index = {}
        idx = 0
        for r in range(4):
            if r >= len(self.round_entries):
                break
            for p in range(len(self.player_order)):
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

    def _on_tab_key(self, event):
        if not getattr(self, "tab_order", None):
            return
        i   = self.entry_index.get(event.widget, 0)
        nxt = (i + 1) % len(self.tab_order)
        self.tab_order[nxt].focus_set()
        return "break"

    def _on_shift_tab_key(self, event):
        if not getattr(self, "tab_order", None):
            return
        i   = self.entry_index.get(event.widget, 0)
        prv = (i - 1) % len(self.tab_order)
        self.tab_order[prv].focus_set()
        return "break"
