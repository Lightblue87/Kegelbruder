"""
app.py – KegelBruederApp (Hauptklasse / Koordinator)

Verantwortlichkeiten:
- Hauptfenster aufbauen (Menü, Toolbar, Punkteingabe-Grid)
- Spielstart, Abort
- Session-Buchungen (Rollback-fähig)
- Delegation der GUI-Bereiche an gui/ Module:
    gui/attendance.py        → AttendanceFlow
    gui/billing.py           → BillingWindow
    gui/cash_management.py   → CashManagementWindow
    gui/archive.py           → ArchiveWindow
    gui/player_management.py → PlayerManagementWindow
    gui/settings.py          → KostenEinstellungenWindow
    gui/game_session.py      → GameSessionFrame
                               (Punkteingabe, Sperre/Entsperre, Snapshot/Restore,
                                Tab-/Fokus-Navigation)
"""

import logging
import tkinter as tk
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP
from tkinter import messagebox, ttk

from cashbox import Kasse
from config import DATA_FILE, HISTORIE_FILE
from data_handler import DatenHandler
from gui.archive import ArchiveWindow
from gui.attendance import AttendanceFlow
from gui.billing import BillingWindow
from gui.cash_management import CashManagementWindow
from gui.game_session import GameSessionFrame
from gui.player_management import PlayerManagementWindow
from gui.settings import KostenEinstellungenWindow
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

        self._kassen_mgmt  = None
        self._game_session = GameSessionFrame(self)

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
        KostenEinstellungenWindow(self.root, self.kasse)

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
        PlayerManagementWindow(self.root)

    def create_punkteingabe(self):
        self._game_session.rebuild()
        self._build_tab_order()

    def entsperre_spielfelder(self):
        self._game_session.entsperre()

    def update_sum(self, player):
        try:
            punkte = [e.get().strip() for e in self.punkte_entries[player][:-1]]
            filled = [p for p in punkte if p != ""]
            if len(filled) == 4 and all(p.isdigit() for p in filled):
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
        # Vorab quantisieren, damit Transaktionsstring und Kassenlogik denselben Wert verwenden
        betrag = float(Decimal(str(betrag)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))
        ok = self.kasse.einzahlung(betrag, beschreibung)
        if not ok:
            return
        if spieler:
            DatenHandler.reduziere_ausstehende_zahlung(spieler, betrag)
        datum      = datetime.now().strftime("%d.%m.%Y")
        entry_plus = f"{datum} | +{betrag:.2f}€: {beschreibung}"
        self._session_tx.append(("einzahlung", betrag, entry_plus))

    def _session_auszahlung(self, betrag: float, beschreibung: str, force: bool = False):
        if betrag <= 0:
            return
        # Vorab quantisieren, damit Transaktionsstring und Kassenlogik denselben Wert verwenden
        betrag = float(Decimal(str(betrag)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))
        ok = self.kasse.auszahlung(betrag, beschreibung, force=force)
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
        self.abrechnung_button.config(state="normal")

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
        self._game_session.sperre(zeige_popup)

    def show_archiv(self):
        ArchiveWindow(self.root)

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
        return self._game_session._snapshot_has_content(snap_players)

    def save_runtime_snapshot(self):
        self._game_session.save_runtime_snapshot()

    def load_runtime_snapshot(self):
        self._game_session.load_runtime_snapshot()

    def _build_tab_order(self):
        self._game_session.build_tab_order()

    def _on_tab_key(self, event):
        return self._game_session._on_tab_key(event)

    def _on_shift_tab_key(self, event):
        return self._game_session._on_shift_tab_key(event)
