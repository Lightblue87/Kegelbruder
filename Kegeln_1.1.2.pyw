#!/usr/bin/env python3
"""
Kegel Brüder App

Spieler- & Kassenverwaltung inkl. Anwesenheit, Abrechnung, Kassenbuch
"""

import tkinter as tk
from tkinter import messagebox, ttk
import json
import os
from datetime import datetime
import logging

# -------------------- Dateien --------------------
DATA_FILE = "kegel_brueder.json"         # Spieler & Kasse (gesamt)
DATA_FILE_KASSE = "kasse.json"           # Kassenstand
AKTUELLES_SPIEL = "aktuelles_spiel.json" # Laufendes Spiel
HISTORIE_FILE = "historie.json"          # Archiv
MITGLIEDER_DATEI = "mitglieder.json"     # Mitgliederverwaltung

# -------------------- Styles --------------------
def setup_styles():
    style = ttk.Style()
    try:
        style.theme_use("clam")
    except tk.TclError:
        pass
    style.configure("TFrame", background="#E8F0FE")
    style.configure("TLabel", background="#E8F0FE", foreground="#2C3E50", font=("Arial", 10))
    style.configure("Header.TLabel", font=("Arial", 14, "bold"), foreground="#4285F4", background="#E8F0FE")
    style.configure("TButton", background="#4285F4", foreground="white", font=("Arial", 10, "bold"))
    style.map("TButton", background=[("active", "#3367D6"), ("disabled", "#A0A0A0")])
    style.configure("TEntry", padding=5, relief="flat", fieldbackground="white", foreground="#2C3E50")
    style.configure("Treeview", background="white", fieldbackground="white", foreground="#2C3E50")
    style.configure("Treeview.Heading", background="#4285F4", foreground="white", font=("Arial", 10, "bold"))

logging.basicConfig(
    filename="kegel_brueder.log",
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

# =============================================================================
# Datenzugriff
# =============================================================================
class DatenHandler:
    @staticmethod
    def _safe_read_json(path, default):
        if os.path.exists(path):
            try:
                with open(path, "r") as f:
                    return json.load(f)
            except json.JSONDecodeError:
                logging.error("Beschädigte JSON-Datei: %s – neu initialisieren.", path)
        with open(path, "w") as f:
            json.dump(default, f, indent=4)
        return default

    @staticmethod
    def laden_mitglieder():
        return DatenHandler._safe_read_json(MITGLIEDER_DATEI, {"players": {}})

    @staticmethod
    def speichern_mitglieder(players):
        try:
            with open(MITGLIEDER_DATEI, "w") as f:
                json.dump({"players": players}, f, indent=4)
        except Exception as e:
            logging.error("Speichern Mitglieder fehlgeschlagen: %s", e)

    @staticmethod
    def laden():
        return DatenHandler._safe_read_json(DATA_FILE, {"players": {}, "kasse": {}})

    @staticmethod
    def laden_spiel():
        # Standard: kein aktives Spiel
        return DatenHandler._safe_read_json(AKTUELLES_SPIEL, {"players": {}, "runde": 0, "abgerechnet": False})

    @staticmethod
    def speichern_spiel(data):
        try:
            with open(AKTUELLES_SPIEL, "w") as f:
                json.dump(data, f, indent=4)
        except Exception as e:
            logging.error("Speichern aktuelles Spiel fehlgeschlagen: %s", e)

    @staticmethod
    def archivieren_spiel(spieldaten):
        historie = DatenHandler._safe_read_json(HISTORIE_FILE, [])
        if "spieler_reihenfolge" not in spieldaten and "players" in spieldaten:
            spieldaten["spieler_reihenfolge"] = list(spieldaten["players"].keys())
        historie.append(spieldaten)
        try:
            with open(HISTORIE_FILE, "w") as f:
                json.dump(historie, f, indent=4)
        except Exception as e:
            logging.error("Speichern Historie fehlgeschlagen: %s", e)

# =============================================================================
# Kassen-Logik
# =============================================================================
class Kasse:
    def __init__(self):
        self.kasse = {
            "Startgeld": 5.0,
            "Pumpe": 0.5,
            "Neuner": 1.0,
            "Kranz": 2.0,
            "Strafe Stamm": 7.5,
            "Bahngebühr": 30.0,
            "Kassenstand": 0.0,
            "Transaktionen": []
        }
        self.lade_kasse()

    def get_bahngebuehr(self) -> float:
        """Robuster Zugriff – unterstützt auch alte Schlüssel/Schreibweisen."""
        return float(
            self.kasse.get("Bahngebühr")                  # übliche Schreibweise
            or self.kasse.get("Bahngebuehr")              # falls mal 'ue' gespeichert wurde
            or self.kasse.get("Bahngeb\u00fchr")          # defensiv (UTF-escape im RAM)
            or 0
        )

    def lade_kasse(self):
        if os.path.exists(DATA_FILE_KASSE):
            try:
                with open(DATA_FILE_KASSE, "r") as f:
                    self.kasse = json.load(f)
            except json.JSONDecodeError:
                self.speichere_kasse()
                return
        else:
            self.speichere_kasse()
            return

        defaults = {
            "Startgeld": 5, "Pumpe": 0.5, "Neuner": 1, "Kranz": 2,
            "Strafe Stamm": 7.5, "Bahngebühr": 30, "Kassenstand": 0,
            "Transaktionen": []
        }
        changed = False
        for k,v in defaults.items():
            if k not in self.kasse:
                self.kasse[k] = v; changed = True
        if not isinstance(self.kasse.get("Transaktionen", []), list):
            self.kasse["Transaktionen"] = []; changed = True
        if changed:
            self.speichere_kasse()

    def speichere_kasse(self):
        try:
            with open(DATA_FILE_KASSE, "w") as f:
                json.dump(self.kasse, f, indent=4)
        except Exception as e:
            logging.error("Speichern Kasse fehlgeschlagen: %s", e)

    def aktualisiere_kasse(self, players):
        # Nur merken, nicht addieren
        total = self.kasse["Startgeld"] * len(players)
        self.kasse["Letzte_Startgebuehren"] = total
        self.speichere_kasse()

    def anpassen_gebuehren(self, kategorie, betrag):
        if kategorie in self.kasse and isinstance(betrag, (int, float)) and betrag >= 0:
            self.kasse[kategorie] = float(betrag)
            self.speichere_kasse()
            return True
        return False

    def einzahlung(self, betrag, beschreibung="Manuelle Einzahlung", spieler=None):
        """
        Fügt Geld zur Kasse hinzu und speichert die Transaktion.
        Bestimmte Beschreibungen (Einnahmen vom Spieltag, Startgelder-Sammelzeile)
        sind reine Info-Einträge ohne Einfluss auf den Kassenstand.
        """
        if betrag <= 0:
            return False

        datum = datetime.now().strftime("%d.%m.%Y")

        # ✅ reine Info-Buchungen (kein Kassenstand-Update)
        info_only = (
            "Einnahmen vom Spieltag" in beschreibung
            or "Startgelder für" in beschreibung
        )
        if info_only:
            self.kasse["Transaktionen"].append(f"{datum} | {betrag:.2f}€: {beschreibung}")
            self.speichere_kasse()
            return True

        # ✅ normale Einzahlung (Kassenstand hoch)
        self.kasse["Kassenstand"] += betrag
        self.kasse["Transaktionen"].append(f"{datum} | +{betrag:.2f}€: {beschreibung}")

        if spieler:
            self.reduziere_ausstehende_zahlung(spieler, betrag)

        self.speichere_kasse()
        return True

    def auszahlung(self, betrag, beschreibung="Manuelle Auszahlung"):
        if 0 < betrag <= self.kasse["Kassenstand"]:
            datum = datetime.now().strftime("%d.%m.%Y")
            self.kasse["Kassenstand"] -= betrag
            self.kasse["Transaktionen"].append(f"{datum} | -{betrag:.2f}€: {beschreibung}")
            self.speichere_kasse()
            return True
        return False

    def reduziere_ausstehende_zahlung(self, player, betrag):
        try:
            data = DatenHandler.laden_mitglieder()
            if player in data["players"]:
                schuld = data["players"][player].get("offene_zahlung", 0.0)
                data["players"][player]["offene_zahlung"] = max(0.0, float(schuld) - float(betrag))
                DatenHandler.speichern_mitglieder(data["players"])
        except Exception as e:
            logging.error("Reduzieren offene Zahlung fehlgeschlagen: %s", e)

    def zeige_ausstehende_beitraege(self, player):
        data = DatenHandler.laden_mitglieder()
        return float(data.get("players", {}).get(player, {}).get("offene_zahlung", 0.0))

    def get_kassenstand(self):
        return float(self.kasse["Kassenstand"])

    def zeige_transaktionen(self, limit=10):
        return self.kasse["Transaktionen"][-limit:]

# =============================================================================
# GUI
# =============================================================================
class KegelBruederApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Kegel Brüder")
        self.root.configure(bg="#f0f0f0")

        # Daten laden
        data = DatenHandler.laden()
        self.players = data.get("players", {})
        self.kasse = Kasse()
        self.kasse.aktualisiere_kasse(self.players)

        self.runde = 0
        self.arrow_buttons = {}
        self.punkte_entries = {}
        self.zusatzfelder = {}
        self.player_order = []

        self.restore_players()
        self.create_menu()
        self.create_widgets()
        self.create_punkteingabe()
        self.load_runtime_snapshot()

        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

        self.tiebreak_extras = {}
        
        self._session_tx = []   # protokolliert alle Buchungen dieser Spielsitzung für Rollback
        self._pre_session_schulden = {}   # Snapshot der offenen Beträge vor Spielbeginn

    # -------------------- Menü --------------------
    def create_menu(self):
        menu = tk.Menu(self.root)
        self.root.config(menu=menu)

        # NEU: Spiel-Menü mit "Spiel abbrechen…"
        spiel_menu = tk.Menu(menu, tearoff=0)
        menu.add_cascade(label="Spiel", menu=spiel_menu)
        spiel_menu.add_command(label="Spiel abbrechen…", command=self.abort_game)

        # Bestehendes Einstellungsmenü bleibt
        einstellungen = tk.Menu(menu, tearoff=0)
        menu.add_cascade(label="Einstellungen", menu=einstellungen)
        einstellungen.add_command(label="Spieler verwalten", command=self.manage_players)
        einstellungen.add_command(label="Kosten Einstellungen", command=self.open_kosten_einstellungen)

    def abort_game(self, silent: bool = False):
        """
        Bricht das laufende Spiel ab:
        - Rollback aller in dieser Session gebuchten Ein-/Auszahlungen (Kassenstand + Transaktionen)
        - EXAKTE Wiederherstellung der offenen Beträge auf den Stand VOR Spielbeginn (Snapshot)
        - Keine Archivierung / keine dauerhafte Buchung
        - UI zurücksetzen
        """
        if not silent:
            if not messagebox.askyesno(
                "Spiel abbrechen",
                "Möchtest du das laufende Spiel wirklich abbrechen?\n"
                "Alle heutigen Buchungen und Änderungen werden zurückgesetzt."
            ):
                return

        # 1) Transaktionen zurückrollen (nur, was wir in _session_tx protokolliert haben)
        try:
            for kind, betrag, expected_text in reversed(getattr(self, "_session_tx", [])):
                if not self.kasse.kasse["Transaktionen"]:
                    continue
                last = self.kasse.kasse["Transaktionen"][-1]
                if last != expected_text:
                    # Unerwartete Reihenfolge → Sicherheitsverhalten: nichts machen
                    continue
                if kind == "einzahlung":
                    self.kasse.kasse["Kassenstand"] = max(
                        0.0, float(self.kasse.kasse["Kassenstand"]) - float(betrag)
                    )
                elif kind == "auszahlung":
                    self.kasse.kasse["Kassenstand"] = float(self.kasse.kasse["Kassenstand"]) + float(betrag)
                self.kasse.kasse["Transaktionen"].pop()
            self.kasse.speichere_kasse()
        except Exception:
            pass
        finally:
            self._session_tx = []

        # 2) Offene Beträge exakt auf Snapshot zurücksetzen
        try:
            if getattr(self, "_pre_session_schulden", None):
                mit = DatenHandler.laden_mitglieder()
                for name, pdata in mit.get("players", {}).items():
                    if name in self._pre_session_schulden:
                        pdata["offene_zahlung"] = float(self._pre_session_schulden[name])
                DatenHandler.speichern_mitglieder(mit["players"])
        except Exception:
            pass
        finally:
            self._pre_session_schulden = {}

        # 3) UI & State zurücksetzen (keine Archivierung)
        try:
            self.sperre_spielfelder(zeige_popup=False)
        except Exception:
            pass
        self.tiebreak_extras = {}
        DatenHandler.speichern_spiel({"players": {}, "runde": 0, "abgerechnet": False})
        self.restore_players()
        self.create_punkteingabe()
        messagebox.showinfo("Abgebrochen", "Das Spiel wurde abgebrochen. Alle Werte sind wieder auf dem Stand vor Spielbeginn.")

    # -------------------- Kosten-Einstellungen --------------------
    def open_kosten_einstellungen(self):
        win = tk.Toplevel(self.root)
        win.title("Kosten Einstellungen")

        ttk.Label(win, text="Hier können die Kosten angepasst werden:", font=("Arial", 12, "bold")
                 ).grid(row=0, column=0, columnspan=2, pady=10)

        fields = ["Startgeld", "Pumpe", "Neuner", "Kranz", "Strafe Stamm", "Bahngebühr"]
        vars_ = {}
        row = 1
        for key in fields:
            if key not in self.kasse.kasse:
                # Defaults, falls in alter Datei nicht vorhanden
                defaults = {
                    "Startgeld": 5.0, "Pumpe": 0.5, "Neuner": 1.0, "Kranz": 2.0,
                    "Strafe Stamm": 7.5, "Bahngebühr": 30.0
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
                        raise ValueError
                    self.kasse.anpassen_gebuehren(key, value)
                except ValueError:
                    messagebox.showerror("Fehler", f"Ungültiger Betrag für {key}.")
                    return
            messagebox.showinfo("Gespeichert", "Kosten erfolgreich aktualisiert.")
            win.destroy()

        ttk.Button(win, text="Speichern", command=save).grid(row=row, column=0, columnspan=2, pady=10)

    # -------------------- Top-Buttons --------------------
    def create_widgets(self):
        ttk.Button(self.root, text="Neues Spiel", command=self.start_new_game).grid(row=0, column=0, pady=5)
        ttk.Button(self.root, text="Kassenverwaltung", command=self.Show_Kassenverwaltung).grid(row=0, column=2, pady=5)

        self.abrechnung_button = ttk.Button(self.root, text="Abrechnung", command=self.show_abrechnung)
        self.abrechnung_button.grid(row=0, column=3, pady=5)

        ttk.Button(self.root, text="Archiv", command=self.show_archiv).grid(row=0, column=4, pady=5)

        gespeichertes_spiel = DatenHandler.laden_spiel()
        if gespeichertes_spiel.get("abgerechnet", False):
            self.abrechnung_button.config(state="disabled")

    # -------------------- Spielerverwaltung --------------------
    def manage_players(self):
        win = tk.Toplevel(self.root)
        win.title("Spieler verwalten")

        # Liste
        self.player_listbox = tk.Listbox(win, height=10, width=50)
        self.player_listbox.grid(row=0, column=0, padx=10, pady=5, columnspan=3, sticky="ew")
        self.update_player_list()

        # Eingaben: Name, Typ, Offener Betrag (nur Stamm)
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
        offener_entry = ttk.Entry(win, textvariable=offener_betrag_var, width=10)
        offener_entry.grid(row=3, column=1, padx=10, pady=5, sticky="w")

        def _toggle_offen(*_):
            # nur bei Stamm editierbar
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
                v = float(s)
                return max(0.0, v)
            except ValueError:
                return 0.0

        def add_player():
            name = name_entry.get().strip()
            typ = player_type.get()
            if not name or typ not in ("Stamm", "Gast"):
                return

            mit = DatenHandler.laden_mitglieder()
            if name in mit["players"]:
                messagebox.showerror("Fehler", "Name existiert bereits.")
                return

            offene = _parse_money(offener_betrag_var.get()) if typ == "Stamm" else 0.0
            mit["players"][name] = {
                "typ": typ,
                "punkte": [0, 0, 0, 0],
                "offene_zahlung": float(offene)
            }
            DatenHandler.speichern_mitglieder(mit["players"])
            self.update_player_list()
            name_entry.delete(0, tk.END)
            offener_betrag_var.set("0,00")
            player_type.set("Stamm")

        def remove_player():
            sel = self.player_listbox.get(tk.ACTIVE)
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
            sel = self.player_listbox.get(tk.ACTIVE)
            selected = sel.split(" (")[0] if sel else ""
            if not selected:
                return
            mit = DatenHandler.laden_mitglieder()
            if selected not in mit["players"]:
                return

            pdata = mit["players"][selected]

            ew = tk.Toplevel(self.root)
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
            offen_edit_var = tk.StringVar(value=f"{float(pdata.get('offene_zahlung', 0.0)):.2f}".replace(".", ","))
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
                new_typ = typ_var.get()
                if not new_name:
                    return

                # umbenennen falls Name geändert wurde
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
        ttk.Button(win, text="Entfernen",  command=remove_player).grid(row=4, column=1, pady=8)
        ttk.Button(win, text="Bearbeiten", command=edit_player).grid(row=4, column=2, pady=8)

    def update_player_list(self):
        if not hasattr(self, "player_listbox"):
            return
        self.player_listbox.delete(0, tk.END)
        mit = DatenHandler.laden_mitglieder().get("players", {})
        for p, d in sorted(mit.items()):
            self.player_listbox.insert(tk.END, f"{p} ({d['typ']})")

    # -------------------- Punkteingabe --------------------
    def create_punkteingabe(self):
        if hasattr(self, "punkte_frame"):
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
        self.zusatzfelder = {}
        # WICHTIG: definierte Reihenfolge benutzen
        if not getattr(self, "player_order", None):
            self.player_order = list(self.players.keys())

        # Hier sammeln wir die Entry-Widgets pro Runde (für Tab-Order)
        self.round_entries = [[] for _ in range(4)]

        row = 2
        self.arrow_buttons = {}
        for player in self.player_order:
            ttk.Label(self.punkte_frame, text=player).grid(row=row, column=0, padx=10, pady=5, sticky="w")

            self.punkte_entries[player] = []
            self.zusatzfelder[player] = {}
            self.arrow_buttons[player] = {}

            # Pumpen/Neuner/Kranz (mit Trace fürs Autosave, falls vorhanden)
            for i, feld in enumerate(["Pumpen", "Neuner", "Kranz"]):
                frame = ttk.Frame(self.punkte_frame)
                frame.grid(row=row, column=i+1, padx=5, pady=5, sticky="ew")
                var = tk.IntVar(value=0)

                # Wenn du bereits save_runtime_snapshot nutzt, hier kurz hooken:
                def _trace_save(*_):
                    try:
                        self.save_runtime_snapshot()
                    except Exception:
                        pass
                try:
                    var.trace_add("write", _trace_save)
                except Exception:
                    pass

                entry = ttk.Entry(frame, width=5, justify="center", textvariable=var, state="readonly")
                entry.pack(side="left")

                def inc(v=var): v.set(v.get()+1)
                def dec(v=var): v.set(max(0, v.get()-1))

                up = ttk.Button(frame, text="▲", width=2, command=lambda v=var: inc(v))
                dn = ttk.Button(frame, text="▼", width=2, command=lambda v=var: dec(v))
                dn.pack(side="right")
                up.pack(side="right")
                self.zusatzfelder[player][feld] = var
                self.arrow_buttons[player][feld] = (up, dn)

            # 4 Runden (Entries sammeln und Tab-Order später bauen)
            for r in range(4):
                e = ttk.Entry(self.punkte_frame, width=10, justify="center")
                e.grid(row=row, column=r+4, padx=5, pady=5, sticky="ew")

                # Autofokus → wenn "0", dann markieren
                def select_all_if_zero(event, entry=e):
                    if entry.get().strip() == "0":
                        entry.selection_range(0, tk.END)

                e.bind("<FocusIn>", select_all_if_zero)

                # Live speichern (falls du Autosave drin hast)
                e.bind("<KeyRelease>", lambda evt, p=player: getattr(self, "save_runtime_snapshot", lambda: None)())
                e.bind("<FocusOut>",  lambda evt, p=player: (self.update_sum(p), getattr(self, "save_runtime_snapshot", lambda: None)()))

                self.punkte_entries[player].append(e)
                self.round_entries[r].append(e)  # <-- WICHTIG: für Tab-Order

            sum_label = ttk.Label(self.punkte_frame, text="0", font=("Arial", 10, "bold"))
            sum_label.grid(row=row, column=8, padx=10, pady=5, sticky="ew")
            self.punkte_entries[player].append(sum_label)

            row += 1

        # Jetzt, nachdem ALLE Entries existieren, Tab-Reihenfolge aufbauen
        self._build_tab_order()

    def entsperre_spielfelder(self):
        """
        Entsperrt alle Spielfelder beim Start eines neuen Spiels:
        - Punkte-Entries wieder aktivieren
        - Pfeil-Buttons für Pumpen/Neuner/Kranz aktivieren
        - Abrechnungsbutton aktivieren
        """

        # Abrechnen-Button aktivieren (falls vorhanden)
        if hasattr(self, "abrechnung_button") and self.abrechnung_button:
            try:
                self.abrechnung_button.config(state="normal")
            except Exception:
                pass
        if hasattr(self, "abrechnen_button") and self.abrechnen_button:
            try:
                self.abrechnen_button.config(state="normal")
            except Exception:
                pass

        # Punkte-Eingabefelder aktivieren (letztes Element ist das Summenlabel)
        for _, entry_list in getattr(self, "punkte_entries", {}).items():
            for entry in entry_list[:-1]:
                try:
                    entry.config(state="normal")
                except Exception:
                    pass

        # Pfeil-Buttons für Zusatzfelder wieder aktivieren
        for _, buttons_for_player in getattr(self, "arrow_buttons", {}).items():
            for _, btn_pair in buttons_for_player.items():
                try:
                    up_btn, down_btn = btn_pair
                except Exception:
                    # Falls das Mapping anders ist, überspringen
                    continue
                if up_btn and up_btn.winfo_exists():
                    try: up_btn.config(state="normal")
                    except Exception: pass
                if down_btn and down_btn.winfo_exists():
                    try: down_btn.config(state="normal")
                    except Exception: pass

        # Sicherstellen, dass die IntVars für Zusatzfelder existieren
        # (falls create_punkteingabe() gerade neu aufgebaut wurde)
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
        except Exception:
            pass

    # -------------------- Kassenverwaltung --------------------
    def Show_Kassenverwaltung(self):
        # Existierendes Fenster schließen, damit keine alten Widgets übrig bleiben
        if hasattr(self, "kassen_window") and self.kassen_window and self.kassen_window.winfo_exists():
            self.kassen_window.destroy()

        win = tk.Toplevel(self.root)
        self.kassen_window = win
        win.title("Kassenverwaltung")
        win.geometry("960x600")
        win.minsize(860, 520)

        # Layout-Grundraster
        for c in range(4):
            win.grid_columnconfigure(c, weight=1)
        win.grid_rowconfigure(2, weight=1)   # Offene Zahlungen (Textfeld)
        win.grid_rowconfigure(8, weight=1)   # Transaktionen (Textfeld)

        # ---------- Kassenstand ----------
        ttk.Label(win, text="Kassenstand:", font=("Arial", 12, "bold")).grid(
            row=0, column=0, padx=10, pady=(10, 5), sticky="w"
        )
        self.kassenstand_label = ttk.Label(
            win, text=f"{self.kasse.get_kassenstand():.2f} €", font=("Arial", 12, "bold")
        )
        self.kassenstand_label.grid(row=0, column=1, columnspan=3, padx=10, pady=(10, 5), sticky="w")

        # ---------- Offene Zahlungen (ein Textfeld + 2 Scrollbars in EINEM Frame) ----------
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

        # ---------- Eingabereihe ----------
        ttk.Label(win, text="Spieler:", font=("Arial", 10)).grid(row=4, column=0, padx=10, pady=(10, 5), sticky="w")
        self.spieler_var = tk.StringVar()
        self.spieler_drop = ttk.Combobox(win, textvariable=self.spieler_var, state="readonly")
        self.spieler_drop.grid(row=4, column=1, padx=10, pady=(10, 5), sticky="ew")

        ttk.Label(win, text="Betrag:", font=("Arial", 10)).grid(row=4, column=2, padx=10, pady=(10, 5), sticky="w")
        self.betrag_entry = ttk.Entry(win)
        self.betrag_entry.grid(row=4, column=3, padx=10, pady=(10, 5), sticky="ew")

        ttk.Label(win, text="Spende:", font=("Arial", 10)).grid(row=5, column=2, padx=10, pady=5, sticky="w")
        self.spende_entry = ttk.Entry(win)
        self.spende_entry.grid(row=5, column=3, padx=10, pady=5, sticky="ew")

        # ---------- Aktionen ----------
        def einzahlen():
            # Betrag reduziert offene Schuld (wenn Spieler gewählt); Spende reduziert NICHT offene Schuld.
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

            spieler = (self.spieler_var.get() or "").strip() or None

            # 1) Betrag – kassenwirksam und reduziert offene_zahlung NUR, wenn Spieler gesetzt
            if betrag > 0:
                beschr = f"Zahlung von {spieler}" if spieler else "Zahlung (ohne Zuordnung)"
                self.kasse.einzahlung(betrag, beschr, spieler=spieler)

            # 2) Spende – kassenwirksam, aber KEINE Reduktion offener Beträge
            if spende > 0:
                beschr_s = f"Spende von {spieler}" if spieler else "Spende"
                self.kasse.einzahlung(spende, beschr_s, spieler=None)

            if betrag > 0 or spende > 0:
                self.update_kassenstand()
                self.update_transaktionen(self.kassen_window)
                self._refresh_offene_widgets()

        def auszahlen():
            try:
                betrag = float((self.betrag_entry.get() or "0").replace(",", "."))
            except ValueError:
                messagebox.showerror("Fehler", "Bitte gültigen Betrag eingeben.")
                return
            if betrag <= 0:
                return
            if not self.kasse.auszahlung(betrag, "Manuelle Auszahlung"):
                messagebox.showerror("Fehler", "Nicht genügend Guthaben.")
                return
            self.update_kassenstand()
            self.update_transaktionen(self.kassen_window)

        btn_row = ttk.Frame(win)
        btn_row.grid(row=6, column=0, columnspan=4, padx=10, pady=10, sticky="w")
        ttk.Button(btn_row, text="Einzahlen", command=einzahlen).pack(side="left", padx=(0, 8))
        ttk.Button(btn_row, text="Auszahlen", command=auszahlen).pack(side="left")

        # ---------- Transaktionen (ein Textfeld + 2 Scrollbars in EINEM Frame) ----------
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

        # Initiale Füllung
        self._refresh_offene_widgets()
        self.update_transaktionen(self.kassen_window)

    def _einzahlen_kasse(self):
        try:
            betrag = float(self.betrag_entry.get().replace(",", "."))
        except ValueError:
            messagebox.showerror("Fehler", "Bitte gültigen Betrag eingeben.")
            return
        spende = 0.0
        if self.spende_entry.get().strip():
            try:
                spende = float(self.spende_entry.get().replace(",", "."))
            except ValueError:
                messagebox.showerror("Fehler", "Bitte gültige Spende eingeben.")
                return
        spieler = (self.spieler_var.get() or "").strip() or None
        gesamt = betrag + spende
        if gesamt <= 0:
            return
        self.kasse.einzahlung(
            gesamt,
            f"Zahlung von {spieler if spieler else 'Gruppe'} ({betrag:.2f} € + Spende {spende:.2f} €)",
            spieler=spieler
        )
        self.update_kassenstand()

    def _auszahlen_kasse(self):
        try:
            betrag = float(self.betrag_entry.get().replace(",", "."))
        except ValueError:
            messagebox.showerror("Fehler", "Bitte gültigen Betrag eingeben.")
            return
        if not self.kasse.auszahlung(betrag, "Manuelle Auszahlung"):
            messagebox.showerror("Fehler", "Nicht genügend Guthaben.")
            return
        self.update_kassenstand()

    def update_transaktionen(self, win=None):
        if not hasattr(self, "trans_widget") or not self.trans_widget.winfo_exists():
            return
        self.trans_widget.config(state=tk.NORMAL)
        self.trans_widget.delete("1.0", tk.END)
        for t in self.kasse.zeige_transaktionen(limit=200):
            self.trans_widget.insert(tk.END, t + "\n")
        self.trans_widget.config(state=tk.DISABLED)
        self.trans_widget.see(tk.END)

    def _lade_offene_stamm(self):
        """
        Liest die offenen Beträge IMMER frisch aus der Mitgliederdatei.
        Liefert (offene_dict, mitglieder_dict).
        """
        mit = DatenHandler.laden_mitglieder().get("players", {})
        offene = {
            p: float(d.get("offene_zahlung", 0.0))
            for p, d in mit.items()
            if d.get("typ") == "Stamm" and float(d.get("offene_zahlung", 0.0)) > 0
        }
        return offene, mit

    def _refresh_offene_widgets(self):
        """
        Aktualisiert Textfeld + Combobox im Kassenfenster anhand der Datei.
        """
        if not hasattr(self, "kassen_window") or not self.kassen_window.winfo_exists():
            return
        offene, _ = self._lade_offene_stamm()

        # Textfeld neu füllen
        if hasattr(self, "offene_txt") and self.offene_txt.winfo_exists():
            self.offene_txt.config(state=tk.NORMAL)
            self.offene_txt.delete("1.0", tk.END)
            for p, betrag in offene.items():
                self.offene_txt.insert(tk.END, f"{p}: {betrag:.2f} €\n")
            self.offene_txt.config(state=tk.DISABLED)

        # Combobox-Optionen neu setzen (nur Spieler mit >0 offen)
        if hasattr(self, "spieler_drop") and self.spieler_drop.winfo_exists():
            self.spieler_drop["values"] = sorted(offene.keys())

    def update_kassenstand(self):
        """
        Aktualisiert den Kassenstand in der GUI – robust gegen bereits geschlossene Widgets.
        """
        try:
            # Fenster vorhanden und sichtbar?
            k_win_ok = getattr(self, "kassen_window", None) and self.kassen_window.winfo_exists()
            lbl_ok   = getattr(self, "kassenstand_label", None) and self.kassenstand_label.winfo_exists()

            if k_win_ok and lbl_ok:
                self.kassenstand_label.config(text=f"{self.kasse.get_kassenstand():.2f} €")

                # Transaktionsliste aktualisieren (egal welcher Methodenname in deiner Version existiert)
                if hasattr(self, "update_transaktionen"):
                    self.update_transaktionen()
                elif hasattr(self, "update_transaktionsliste"):
                    self.update_transaktionsliste()
            # Wenn das Fenster/Label nicht existiert, nichts tun – kein Fehler.
        except tk.TclError:
            # Widget wurde währenddessen zerstört → ignorieren
            pass

    def _session_reset(self):
        """Session-Log leeren (nach erfolgreicher Abrechnung ODER vor neuem Spiel)."""
        self._session_tx = []

    def _session_einzahlung(self, betrag: float, beschreibung: str, spieler=None):
        """Einzahlung buchen UND in der Session protokollieren (für Rollback)."""
        if betrag <= 0:
            return
        # echte Buchung
        ok = self.kasse.einzahlung(betrag, beschreibung, spieler=spieler)
        if not ok:
            return
        # den *genauen* Transaktionstext wie gespeichert rekonstruieren
        datum = datetime.now().strftime("%d.%m.%Y")
        # Info-Zeilen haben kein +/-, die wollen wir i.d.R. nicht in einer Session vormerken.
        # Wir merken nur echte Kassenbewegungen (+/-) vor:
        entry_plus = f"{datum} | +{betrag:.2f}€: {beschreibung}"
        self._session_tx.append(("einzahlung", betrag, entry_plus))

    def _session_auszahlung(self, betrag: float, beschreibung: str):
        """Auszahlung buchen UND in der Session protokollieren (für Rollback)."""
        if betrag <= 0:
            return
        ok = self.kasse.auszahlung(betrag, beschreibung)
        if not ok:
            return
        datum = datetime.now().strftime("%d.%m.%Y")
        entry_minus = f"{datum} | -{betrag:.2f}€: {beschreibung}"
        self._session_tx.append(("auszahlung", betrag, entry_minus))

    # -------------------- Anwesenheit & Reihenfolge --------------------
    def start_new_game(self):
        gespeichertes_spiel = DatenHandler.laden_spiel()
        if gespeichertes_spiel.get("players"):
            messagebox.showinfo("Info", "Ein Spiel läuft bereits. Bitte erst beenden oder Abrechnung durchführen.")
            return

        # entsperren + Grund-GUI frisch
        self.entsperre_spielfelder()

        mit = DatenHandler.laden_mitglieder().get("players", {})
        if not mit:
            messagebox.showinfo("Info", "Keine Spieler vorhanden.")
            return

        # nur für die Eingabemaske (Anzeige) – noch KEIN aktives Spiel!
        self.players = dict(sorted(mit.items()))
        self.player_order = list(self.players.keys())
        self.create_punkteingabe()

        # Anwesenheit/Sortierung erfassen (öffnet Dialog)
        self.show_anwesenheit()

    def toggle_zahlungseingabe(self, player):
        betrag_var, schulden_label, entry = self.bezahlung_vars[player]
        if self.anwesenheit_vars[player].get():
            entry.config(state="normal")
        else:
            entry.config(state="disabled")

    def add_gastspieler(self, parent_frame):
        gast = self.gastspieler_dropdown.get()
        if gast and gast not in self.gastspieler_vars:
            self.gastspieler_vars.append(gast)
            row = len(self.gastspieler_vars)
            ttk.Label(self.gastspieler_frame, text=gast).grid(row=row, column=0, padx=10, pady=5, sticky="w")
            lab = ttk.Label(self.gastspieler_frame, text=f"Offen: {self.kasse.kasse['Startgeld']:.2f} €", foreground="red")
            lab.grid(row=row, column=1, padx=10)
            val = tk.StringVar(value="0,00")
            ent = ttk.Entry(self.gastspieler_frame, textvariable=val, width=10)
            ent.grid(row=row, column=2, padx=10)
            self.bezahlung_vars[gast] = (val, lab, ent)
            self.gastspieler_dropdown.set("")

    def verarbeite_anwesenheit(self):
        aktive = [p for p, v in self.anwesenheit_vars.items() if v.get()] + self.gastspieler_vars
        if not aktive:
            messagebox.showerror("Fehler", "Es muss mindestens ein Spieler anwesend sein!")
            return

        gespeicherte = DatenHandler.laden_mitglieder().get("players", {})
        for p, d in gespeicherte.items():
            if p not in self.players:
                self.players[p] = d

        startgeld = float(self.kasse.kasse["Startgeld"])
        strafe = float(self.kasse.kasse["Strafe Stamm"])

        # Offene Beträge anpassen (Startgeld für Anwesende, Strafe für abwesende Stammspieler)
        for p in self.players:
            self.players[p].setdefault("offene_zahlung", 0.0)
            if p in aktive:
                self.players[p]["offene_zahlung"] += startgeld
            elif self.players[p]["typ"] == "Stamm":
                self.players[p]["offene_zahlung"] += strafe

        # Zahlungen verbuchen (über Session, damit rückrollbar)
        for p, (betrag_var, schulden_label, entry) in self.bezahlung_vars.items():
            try:
                bezahlt = float(betrag_var.get().replace(",", "."))
            except ValueError:
                bezahlt = 0.0
            offen = float(self.players.get(p, {}).get("offene_zahlung", 0.0))
            if bezahlt > 0:
                if bezahlt >= offen:
                    self._session_einzahlung(bezahlt, f"Zahlung von {p}", spieler=p)
                    schulden_label.config(text="Offen: 0,00 €", foreground="green")
                    self.players[p]["offene_zahlung"] = 0.0
                else:
                    rest = offen - bezahlt
                    self._session_einzahlung(bezahlt, f"Teilzahlung von {p}", spieler=p)
                    self.players[p]["offene_zahlung"] = rest
                    schulden_label.config(text=f"Offen: {rest:.2f} €", foreground="red")

        DatenHandler.speichern_mitglieder(self.players)
        # Reihenfolge wählen
        self.sort_players_window(self.anwesenheit_window)

    def show_anwesenheit(self):
        """
        Anwesenheit erfassen:
        - OBEN: nur Stamm-Spieler
        - 'Heute gezahlt' ist deaktiviert, bis 'Anwesend' angehakt ist
        - 'Offen' zeigt (offene_zahlung + Startgeld, falls anwesend) LIVE an
        - UNTEN: Gäste hinzufügen; Gäste-Zeilen sind spaltenbündig zu Stamm (inkl. 'Heute gezahlt')
        - Buttons (Abbrechen/Weiter) immer am unteren Fensterrand
        """
        # --- NEU: Snapshot aller offenen Beträge vor jeglicher Session-Aktion ---
        try:
            mit = DatenHandler.laden_mitglieder().get("players", {})
            self._pre_session_schulden = {
                name: float(pdata.get("offene_zahlung", 0.0))
                for name, pdata in mit.items()
            }
        except Exception:
            self._pre_session_schulden = {}
    
        win = tk.Toplevel(self.root)
        win.title("Anwesenheit")
        win.grab_set()
        self.anwesenheit_window = win

        # Haupt-Container (oben Inhalt, unten Buttonleiste)
        content = ttk.Frame(win)
        content.pack(side="top", fill="both", expand=True, padx=12, pady=(10, 6))

        bottom = ttk.Frame(win)
        bottom.pack(side="bottom", fill="x", padx=12, pady=(0, 10))

        # Kopfzeilen
        ttk.Label(content, text="Spieler",           font=("Arial", 10, "bold")).grid(row=0, column=0, padx=6, pady=2, sticky="w")
        ttk.Label(content, text="Typ",               font=("Arial", 10, "bold")).grid(row=0, column=1, padx=6, pady=2, sticky="w")
        ttk.Label(content, text="Anwesend",          font=("Arial", 10, "bold")).grid(row=0, column=2, padx=6, pady=2, sticky="w")
        ttk.Label(content, text="Heute gezahlt (€)", font=("Arial", 10, "bold")).grid(row=0, column=3, padx=6, pady=2, sticky="w")
        ttk.Label(content, text="Offen",             font=("Arial", 10, "bold")).grid(row=0, column=4, padx=6, pady=2, sticky="w")

        # States
        self.anwesenheit_vars = {}  # {name: tk.BooleanVar}
        self.bezahlung_vars  = {}   # {name: (betrag_var(StringVar), offen_label(Label), entry)}
        self.gastspieler_vars = []  # [namen]

        startgeld = float(self.kasse.kasse.get("Startgeld", 5.0))
        mit = DatenHandler.laden_mitglieder().get("players", {})

        # --- Helper: Offentext aktualisieren (offen + ggf. Startgeld) ---
        def _update_offen_label(name):
            pdata = DatenHandler.laden_mitglieder().get("players", {}).get(name, {})
            offen_bisher = float(pdata.get("offene_zahlung", 0.0))
            add = startgeld if self.anwesenheit_vars[name].get() else 0.0
            gesamt = round(offen_bisher + add, 2)
            lbl = self.bezahlung_vars[name][1]
            lbl.config(text=f"{gesamt:.2f} €", foreground=("red" if gesamt > 0 else "green"))

        # ------- Stamm-Spielerzeilen -------
        row = 1
        for name, pdata in sorted(mit.items()):
            if pdata.get("typ", "Stamm") != "Stamm":
                continue  # Gäste oben nicht anzeigen

            ttk.Label(content, text=name).grid(row=row, column=0, padx=6, pady=2, sticky="w")
            ttk.Label(content, text="Stamm").grid(row=row, column=1, padx=6, pady=2, sticky="w")

            var_anw = tk.BooleanVar(value=False)
            def _mk_toggle(n=name):
                return lambda: (
                    self.bezahlung_vars[n][2].config(state=("normal" if self.anwesenheit_vars[n].get() else "disabled")),
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

        # ------- Gäste-Bereich: Steuerzeile -------
        ttk.Separator(content).grid(row=row, column=0, columnspan=5, sticky="ew", pady=(8, 6))
        row += 1

        ttk.Label(content, text="Gast hinzufügen:").grid(row=row, column=0, padx=6, pady=2, sticky="w")
        alle_gaeste = sorted([n for n, d in mit.items() if d.get("typ") == "Gast"])
        self.gastspieler_dropdown = ttk.Combobox(content, values=alle_gaeste, state="readonly")
        self.gastspieler_dropdown.grid(row=row, column=1, columnspan=2, padx=6, pady=2, sticky="ew")

        # Container, in den die Gastzeilen spaltenbündig eingefügt werden
        guests_frame = ttk.Frame(content)
        guests_frame.grid(row=row+1, column=0, columnspan=5, sticky="ew")
        guests_frame.grid_columnconfigure(0, weight=1)
        # Wir zählen Gastzeilen separat
        self._guest_row_idx = 0

        def add_guest():
            gast = self.gastspieler_dropdown.get()
            if not gast or gast in self.gastspieler_vars:
                return
            self.gastspieler_vars.append(gast)

            r = self._guest_row_idx
            # Spaltenbündig wie oben: Spieler, Typ, (kein Anwesend-Häkchen bei Gast), Heute gezahlt, Offen
            ttk.Label(guests_frame, text=gast).grid(row=r, column=0, padx=6, pady=2, sticky="w")
            ttk.Label(guests_frame, text="Gast").grid(row=r, column=1, padx=6, pady=2, sticky="w")
            # Spalte 2 (Anwesend) bleibt leer, damit Spaltenflucht stimmt
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
        row += 2  # eine Zeile für guests_frame ist belegt

        # etwas Luft vor der Buttonleiste
        ttk.Separator(content).grid(row=row, column=0, columnspan=5, sticky="ew", pady=(8, 0))

        # ------- Buttonleiste IMMER unten -------
        ttk.Button(bottom, text="Abbrechen",
                command=lambda: (win.destroy(), self.abort_game(silent=True))
                ).pack(side="right", padx=(0, 8))
        ttk.Button(bottom, text="Weiter", command=self.verarbeite_anwesenheit
                ).pack(side="right")

    def sort_players_window(self, anwesenheit_window):
        active_players = [p for p, v in self.anwesenheit_vars.items() if v.get()] + self.gastspieler_vars
        if not active_players:
            messagebox.showerror("Fehler", "Es muss mindestens ein Spieler anwesend sein!")
            return

        anwesenheit_window.destroy()

        win = tk.Toplevel(self.root)
        win.title("Spielreihenfolge festlegen")
        win.geometry("400x450")

        ttk.Label(win, text="Spielerreihenfolge:", font=("Arial", 12, "bold")).pack(pady=10)
        self.reihenfolge_listbox = tk.Listbox(win, height=10)
        self.reihenfolge_listbox.pack(pady=5, padx=20, fill="both", expand=True)

        letzte = self.lade_letzte_reihenfolge()
        lst = sorted(active_players, key=lambda x: (letzte.index(x) if x in letzte else 99))
        for p in lst:
            self.reihenfolge_listbox.insert(tk.END, p)

        bf = ttk.Frame(win)
        bf.pack(pady=5)
        ttk.Button(bf, text="▲ Hoch", command=lambda: self.move_player(-1)).pack(side="left", padx=5)
        ttk.Button(bf, text="▼ Runter", command=lambda: self.move_player(1)).pack(side="left", padx=5)
        ttk.Button(win, text="Spiel starten", command=lambda: self.start_game(win)).pack(pady=10)

    def move_player(self, direction):
        sel = self.reihenfolge_listbox.curselection()
        if not sel:
            return
        idx = sel[0]
        new_idx = idx + direction
        if 0 <= new_idx < self.reihenfolge_listbox.size():
            p = self.reihenfolge_listbox.get(idx)
            self.reihenfolge_listbox.delete(idx)
            self.reihenfolge_listbox.insert(new_idx, p)
            self.reihenfolge_listbox.select_set(new_idx)

    def start_game(self, window):
        aktive = list(self.reihenfolge_listbox.get(0, tk.END))
        if not aktive:
            messagebox.showerror("Fehler", "Es muss mindestens ein Spieler anwesend sein!")
            return

        # >>> Reset der Stech-Zähler für ein frisches Spiel
        self.tiebreak_extras = {}

        # Nur aktive Spieler in das Spiel übernehmen
        self.players = {}
        for p in aktive:
            self.players[p] = {
                "typ": "Stamm" if p in self.anwesenheit_vars else "Gast",
                "punkte": [0, 0, 0, 0],
                "offene_zahlung": float(self.players.get(p, {}).get("offene_zahlung", 0.0)),
                "position": aktive.index(p) + 1
            }

        DatenHandler.speichern_spiel({"players": self.players, "runde": 1, "abgerechnet": False})
        self.runde = 1

        self.create_punkteingabe()
        self.kasse.aktualisiere_kasse(self.players)
        self.save_results()
        window.destroy()

    # -------------------- Abrechnung --------------------
    def show_abrechnung(self):
        """Abrechnungsfenster:
        - Platzierung nach ggf. Stechen (Stech-Würfe wurden in self.tiebreak_extras gesammelt)
        - 'Zu zahlen' enthält Strafen inkl. Stech-Würfe
        - Anzeige der Punkte = nur die 4 Runden (ohne Stechpunkte)
        """
        # --- NEU: Guard – keine Eingaben in Runde 1–4? -> Spiel abbrechen + Hinweis
        def _hat_irgendwer_punkte():
            for p, entries in self.punkte_entries.items():
                # nur die vier Rundeneingaben (ohne Summenlabel)
                runden = [e.get().strip() for e in entries[:-1]]
                if any(val != "" for val in runden):   # irgendwer hat etwas eingetragen
                    return True
            return False

        if not _hat_irgendwer_punkte():
            messagebox.showinfo(
                "Keine Rundenpunkte",
                "Es wurden in den Feldern 'Runde 1' bis 'Runde 4' keine Punkte eingegeben.\n"
                "Das Spiel wird abgebrochen."
            )
            # leiser Abbruch (ohne zweite Rückfrage)
            self.abort_game(silent=True)
            return

        # 1) Stechen ggf. durchführen (füllt self.tiebreak_extras)
        final_order = self.resolve_points_tiebreak()

        # 2) Kosten berechnen (jetzt inkl. Stech-Zähler)
        spieler_kosten = self.berechne_abrechnung()

        # Daten: (Platz, Spieler, Zu-zahlen, Punkte_regulär)
        data = []
        for platz, spieler in enumerate(final_order, start=1):
            punkte_reg = sum(self.players[spieler].get("punkte", [0, 0, 0, 0]))
            data.append((platz, spieler, float(spieler_kosten.get(spieler, 0.0)), punkte_reg))

        data.sort(key=lambda x: x[0], reverse=True)  # letzter Platz oben

        self.abrechnung_window = tk.Toplevel(self.root)
        self.abrechnung_window.title("Spielerabrechnung")

        headers = ["Platz", "Spieler", "Zu zahlen (€)", "Gezahlt (€)", "Spende (€)", "Punkte"]
        for i, header in enumerate(headers):
            ttk.Label(self.abrechnung_window, text=header, font=("Arial", 10, "bold")
                    ).grid(row=0, column=i, padx=5, pady=5, sticky="ew")

        self.abrechnung_entries = {}
        self.spenden_labels = {}

        def berechne_spende_zeile(player, gezahlt_var, spende_var, zu_zahlen):
            try:
                gez = float((gezahlt_var.get() or "0").replace(",", "."))
            except ValueError:
                gez = 0.0
            sp = max(0.0, round(gez - float(zu_zahlen), 2))
            spende_var.set(f"{sp:.2f} €")

        row = 1
        for platz, spieler, kosten, punkte_reg in data:
            ttk.Label(self.abrechnung_window, text=str(platz)).grid(row=row, column=0, padx=5, pady=5, sticky="w")
            ttk.Label(self.abrechnung_window, text=spieler).grid(row=row, column=1, padx=5, pady=5, sticky="w")
            ttk.Label(self.abrechnung_window, text=f"{kosten:.2f} €").grid(row=row, column=2, padx=5, pady=5, sticky="ew")

            gezahlt_var = tk.StringVar(value="0,00")
            gezahlt_entry = ttk.Entry(self.abrechnung_window, textvariable=gezahlt_var, width=10)
            gezahlt_entry.grid(row=row, column=3, padx=5, pady=5, sticky="ew")

            spende_var = tk.StringVar(value="0,00")
            ttk.Label(self.abrechnung_window, textvariable=spende_var, foreground="green"
                    ).grid(row=row, column=4, padx=5, pady=5, sticky="ew")

            ttk.Label(self.abrechnung_window, text=str(punkte_reg)).grid(row=row, column=5, padx=5, pady=5, sticky="w")

            gezahlt_entry.bind("<FocusOut>",
                lambda e, p=spieler, g=gezahlt_var, s=spende_var, z=kosten: berechne_spende_zeile(p, g, s, z))

            self.abrechnung_entries[spieler] = (kosten, gezahlt_var)
            self.spenden_labels[spieler] = spende_var
            row += 1

        ttk.Button(self.abrechnung_window, text="Abrechnen",
                command=self.abrechnung_speichern
                ).grid(row=row, column=0, columnspan=len(headers), pady=10)

    def berechne_abrechnung(self):
        """
        Liefert pro Spieler den zu zahlenden Betrag (float),
        inklusive aller im Stechen erzielten Pumpen/Neuner/Kränze.
        """
        kosten = {p: 0.0 for p in self.players}

        # Preise
        preis_pumpe  = float(self.kasse.kasse["Pumpe"])
        preis_neuner = float(self.kasse.kasse["Neuner"])
        preis_kranz  = float(self.kasse.kasse["Kranz"])

        # Zähler (Basis + Stechen) pro Spieler ermitteln
        counts = {}
        for p in self.players:
            pumpen_anz = int(self.zusatzfelder[p]["Pumpen"].get()) + self._stechen_count(p, "pumpen")
            neuner_anz = int(self.zusatzfelder[p]["Neuner"].get()) + self._stechen_count(p, "neuner")
            kranz_anz  = int(self.zusatzfelder[p]["Kranz"].get())  + self._stechen_count(p, "kranz")
            counts[p] = (pumpen_anz, neuner_anz, kranz_anz)

        # 1) Eigene Pumpen zahlt nur der Werfer
        for p, (pumpen_anz, _, _) in counts.items():
            kosten[p] += pumpen_anz * preis_pumpe

        # 2) Neuner/Kränze des Werfers zahlen alle anderen
        for werfer, (_, neuner_anz, kranz_anz) in counts.items():
            aufschlag = neuner_anz * preis_neuner + kranz_anz * preis_kranz
            if aufschlag <= 0:
                continue
            for zahler in self.players:
                if zahler == werfer:
                    continue
                kosten[zahler] += aufschlag

        return kosten
    
    def berechne_strafen_anteile(self):
        """
        Liefert pro Spieler den Betrag, den er als Strafe zahlen muss
        (eigene Pumpen + Anteile an fremden Neunern/Kränzen), inkl. Stechen.
        """
        anteil = {p: 0.0 for p in self.players}

        preis_pumpe  = float(self.kasse.kasse["Pumpe"])
        preis_neuner = float(self.kasse.kasse["Neuner"])
        preis_kranz  = float(self.kasse.kasse["Kranz"])

        # Zähler (Basis + Stechen) pro Spieler
        counts = {}
        for p in self.players:
            pumpen_anz = int(self.zusatzfelder[p]["Pumpen"].get()) + self._stechen_count(p, "pumpen")
            neuner_anz = int(self.zusatzfelder[p]["Neuner"].get()) + self._stechen_count(p, "neuner")
            kranz_anz  = int(self.zusatzfelder[p]["Kranz"].get())  + self._stechen_count(p, "kranz")
            counts[p] = (pumpen_anz, neuner_anz, kranz_anz)

        # Eigene Pumpen → selbst zahlen
        for p, (pumpen_anz, _, _) in counts.items():
            anteil[p] += pumpen_anz * preis_pumpe

        # Neuner/Kränze anderer → zahlen alle außer dem Werfer
        for werfer, (_, neuner_anz, kranz_anz) in counts.items():
            aufschlag = neuner_anz * preis_neuner + kranz_anz * preis_kranz
            if aufschlag <= 0:
                continue
            for zahler in self.players:
                if zahler == werfer:
                    continue
                anteil[zahler] += aufschlag

        return anteil

    def abrechnung_speichern(self):
        """
        Speichert die Abrechnung:
        - Strafen/Spenden/Bahngebühr kassenwirksam (über Session-Wrapper)
        - Startgelder & Gesamteinnahmen nur als Info-Zeilen (ohne Kassenwirkung)
        - inkl. Stech-Würfe
        """
        datum = datetime.now().strftime("%d.%m.%Y")

        tiebreak = getattr(self, "tiebreak_extras", {}) or {}
        def stechen_count(player, key):
            return (tiebreak.get(player) or {}).get(key, 0)

        preis_pumpe  = float(self.kasse.kasse.get("Pumpe", 0))
        preis_neuner = float(self.kasse.kasse.get("Neuner", 0))
        preis_kranz  = float(self.kasse.kasse.get("Kranz", 0))

        # Zähler (Basis + Stechen) je Spieler
        counts = {}
        for p in self.players:
            pumpen_anz = int(self.zusatzfelder[p]["Pumpen"].get()) + stechen_count(p, "pumpen")
            neuner_anz = int(self.zusatzfelder[p]["Neuner"].get()) + stechen_count(p, "neuner")
            kranz_anz  = int(self.zusatzfelder[p]["Kranz"].get())  + stechen_count(p, "kranz")
            counts[p]  = (pumpen_anz, neuner_anz, kranz_anz)

        # Kosten je Spieler
        kosten = {p: 0.0 for p in self.players}

        # Eigene Pumpen -> selbst
        for p, (pumpen_anz, _, _) in counts.items():
            kosten[p] += pumpen_anz * preis_pumpe

        # Neuner/Kränze eines Werfers -> zahlen alle anderen
        for werfer, (_, neuner_anz, kranz_anz) in counts.items():
            aufschlag = neuner_anz * preis_neuner + kranz_anz * preis_kranz
            if aufschlag <= 0:
                continue
            for zahler in self.players:
                if zahler == werfer:
                    continue
                kosten[zahler] += aufschlag

        # 1) Startgelder nur als Info (ohne Kassenwirkung)
        startgeld_info = float(self.kasse.kasse.get("Letzte_Startgebuehren", 0.0) or 0.0)
        if startgeld_info > 0:
            self.kasse.kasse["Transaktionen"].append(
                f"{datum} | {startgeld_info:.2f}€: Startgelder für {len(self.players)} Spieler"
            )
            self.kasse.speichere_kasse()

        # 2) Strafen (kassenwirksam, via Session)
        gesamt_strafen = 0.0
        for player, betrag in kosten.items():
            betrag = round(float(betrag), 2)
            if betrag > 0:
                self._session_einzahlung(betrag, f"{datum} - Strafenanteil von {player}")
                gesamt_strafen += betrag

        # 3) Spenden (positiver Überhang)
        gesamt_spenden = 0.0
        for player, (zu_zahlen, gezahlt_var) in self.abrechnung_entries.items():
            try:
                gezahlt = float((gezahlt_var.get() or "0").replace(",", "."))
            except Exception:
                gezahlt = 0.0
            spende = round(gezahlt - float(zu_zahlen), 2)
            if spende > 0:
                self._session_einzahlung(spende, f"{datum} - Spende von {player}")
                gesamt_spenden += spende

        # 4) Bahngebühr als Auszahlung (via Session)
        bahn = 0.0
        for key in ("Bahngebühr", "Bahngeb\u00fchr"):
            if key in self.kasse.kasse:
                try:
                    bahn = float(self.kasse.kasse[key] or 0.0)
                except Exception:
                    bahn = 0.0
                if bahn:
                    break
        if bahn > 0:
            self._session_auszahlung(bahn, f"{datum} - Bahngebühr")

        # 5) Gesamteinnahmen des Spieltags (nur Info-Zeile)
        info_summe = round(gesamt_strafen + gesamt_spenden + startgeld_info, 2)
        if info_summe > 0:
            self.kasse.einzahlung(info_summe, f"{datum} - Einnahmen vom Spieltag")  # Info-only; kein Kassenstand-Change

        # GUI & Archiv
        if hasattr(self, "kassen_window") and getattr(self, "kassen_window").winfo_exists():
            self.kassenstand_label.config(text=f"{self.kasse.get_kassenstand():.2f} €")
            if hasattr(self, "update_transaktionen"):
                self.update_transaktionen()

        try:
            archivierte_spieler = {p: self.players[p] for p in self.players}
            DatenHandler.archivieren_spiel({
                "datum": datum,
                "players": archivierte_spieler,
                "transaktionen": list(self.kasse.kasse.get("Transaktionen", []))
            })
        except Exception:
            pass

        # Felder sperren & Meldung
        self.sperre_spielfelder()
        messagebox.showinfo(
            "Abrechnung",
            "Abrechnung gespeichert. Strafen, Spenden & Bahngebühr verbucht.\n"
            "Alle Felder gesperrt – starte ein neues Spiel, um fortzufahren."
        )

        # Spiel zurücksetzen, Sitzung COMMIT (Session-Log leeren)
        DatenHandler.speichern_spiel({"players": {}, "runde": 1})
        if hasattr(self, "abrechnung_window") and self.abrechnung_window.winfo_exists():
            self.abrechnung_window.destroy()
        self.tiebreak_extras = {}
        self._session_reset()
        # ... nachdem alles verbucht und archiviert wurde:
        self._session_tx = []
        self._pre_session_schulden = {}   # Snapshot nicht mehr nötig – Spiel ist abgeschlossen

    def sperre_spielfelder(self, zeige_popup: bool = True):
        """
        Sperrt alle Spielfelder nach der Abrechnung, bis ein neues Spiel gestartet wird.
        Mit `zeige_popup=False` gibt es kein eigenes Info-Fenster (für kombinierte Meldung).
        """
        # Abrechnen-Button (falls vorhanden) deaktivieren
        if hasattr(self, "abrechnung_button"):
            self.abrechnung_button.config(state="disabled")
        if hasattr(self, "abrechnen_button"):
            self.abrechnen_button.config(state="disabled")

        # Zusatzfelder (Pumpen/Neuner/Kranz) sperren und Pfeile deaktivieren
        for player in getattr(self, "players", {}):
            if player in getattr(self, "zusatzfelder", {}):
                for feld in ("Pumpen", "Neuner", "Kranz"):
                    try:
                        self.zusatzfelder[player][feld].set(0)
                        # vorhandene Traces entfernen
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

        # Punkte-Eingabefelder sperren (Summenlabel bleibt)
        for _, entry_list in getattr(self, "punkte_entries", {}).items():
            for entry in entry_list[:-1]:
                try:
                    entry.config(state="disabled")
                except Exception:
                    pass

        if zeige_popup:
            messagebox.showinfo("Spiel gesperrt", "Alle Felder gesperrt. Starte ein neues Spiel, um fortzufahren.")

    # -------------------- Archiv --------------------
    def show_archiv(self):
        win = tk.Toplevel(self.root)
        win.title("Archiv")
        win.geometry("800x600")

        data = DatenHandler._safe_read_json(HISTORIE_FILE, [])
        try:
            data = sorted(data, key=lambda e: datetime.strptime(e.get("datum", "01.01.1900"), "%d.%m.%Y"), reverse=True)
        except Exception:
            pass

        overview = ttk.Treeview(win, columns=("Datum", "Spieler", "Transaktionen"), show="headings")
        overview.heading("Datum", text="Datum")
        overview.heading("Spieler", text="Spieleranzahl")
        overview.heading("Transaktionen", text="Transaktionen")
        overview.column("Datum", width=110, anchor="center")
        overview.column("Spieler", width=110, anchor="center")
        overview.column("Transaktionen", width=140, anchor="center")
        overview.pack(side="left", fill="y", padx=10, pady=10)

        for entry in data:
            datum = entry.get("datum", "unbekannt")
            num_players = len(entry.get("players", {}))
            num_trans = len(entry.get("transaktionen", []))
            overview.insert("", "end", values=(datum, num_players, num_trans))

        details = ttk.Frame(win)
        details.pack(side="top", fill="both", expand=True, padx=10, pady=10)

        ttk.Label(details, text="Finale Platzierung", font=("Arial", 10, "bold")).pack(pady=5)

        place_tree = ttk.Treeview(details, columns=("Platz", "Spieler", "Einzelpunkte", "Summe", "Pumpen"), show="headings", height=8)
        for col, txt, w, anchor in [
            ("Platz", "Platz", 60, "center"),
            ("Spieler", "Spieler", 140, "w"),
            ("Einzelpunkte", "Einzelpunkte", 160, "w"),
            ("Summe", "Punktesumme", 100, "center"),
            ("Pumpen", "Pumpen", 80, "center"),
        ]:
            place_tree.heading(col, text=txt)
            place_tree.column(col, width=w, anchor=anchor)
        place_tree.tag_configure("topPump", background="lightblue")
        place_tree.pack(fill="x", padx=10, pady=5)

        ttk.Label(details, text="Transaktionen", font=("Arial", 10, "bold")).pack(pady=5)
        tx_tree = ttk.Treeview(details, columns=("Transaktion",), show="headings", height=8)
        tx_tree.heading("Transaktion", text="Transaktion")
        tx_tree.column("Transaktion", anchor="w", width=500)
        tx_tree.pack(fill="both", expand=True, padx=10, pady=5)

        def on_select(event):
            sel = overview.selection()
            if not sel:
                return
            values = overview.item(sel[0], "values")
            datum = values[0]

            for entry in data:
                if entry.get("datum") == datum:
                    # Clear
                    for n in place_tree.get_children():
                        place_tree.delete(n)
                    for n in tx_tree.get_children():
                        tx_tree.delete(n)

                    order = entry.get("spieler_reihenfolge") or list(entry.get("players", {}).keys())
                    pump_counts = {p: entry.get("players", {}).get(p, {}).get("pumpen", 0) for p in entry.get("players", {})}
                    top_two = [p for p, _ in sorted(pump_counts.items(), key=lambda x: x[1], reverse=True)[:2]]

                    for rank, player in enumerate(order, start=1):
                        pdata = entry.get("players", {}).get(player, {})
                        punkte_list = pdata.get("punkte", [])
                        punkte_str = ", ".join(map(str, punkte_list))
                        punkte_sum = sum(punkte_list) if punkte_list else 0
                        pumps = pdata.get("pumpen", 0)
                        tags = ("topPump",) if player in top_two else ()
                        place_tree.insert("", "end", values=(rank, player, punkte_str, punkte_sum, pumps), tags=tags)

                    for t in entry.get("transaktionen", []):
                        tx_tree.insert("", "end", values=(t,))
                    break

        overview.bind("<<TreeviewSelect>>", on_select)

        ttk.Button(win, text="Schließen", command=win.destroy).pack(side="bottom", pady=10)

    def _stechen_runde_dialog(self, teilnehmer, art="punkte"):
        """
        Zeigt ein kleines Fenster für EINE Stechen-Runde.
        Rückgabe: dict[player] = {"punkte": int, "pumpen": int, "neuner": int, "kraenze": int}
        Garantiert: Es gibt für JEDEN Teilnehmer einen Eintrag (bei Abbruch alles 0).
        """
        win = tk.Toplevel(self.root)
        win.title(f"Stechen – Runde (Art: {art})")
        win.grab_set()

        headers = ["Spieler", "Punkte (3 Würfe)", "Pumpen", "Neuner", "Kranz"]
        for c, h in enumerate(headers):
            ttk.Label(win, text=h, font=("Arial", 10, "bold")).grid(row=0, column=c, padx=6, pady=4, sticky="w")

        eingaben = {}
        for r, p in enumerate(teilnehmer, start=1):
            ttk.Label(win, text=p).grid(row=r, column=0, padx=6, pady=3, sticky="w")
            v_punkte = tk.StringVar(value="0")
            v_pumpen = tk.StringVar(value="0")
            v_neuner = tk.StringVar(value="0")
            v_kraenz = tk.StringVar(value="0")
            ttk.Entry(win, textvariable=v_punkte, width=8).grid(row=r, column=1, padx=4, pady=3)
            ttk.Entry(win, textvariable=v_pumpen, width=6).grid(row=r, column=2, padx=4, pady=3)
            ttk.Entry(win, textvariable=v_neuner, width=6).grid(row=r, column=3, padx=4, pady=3)
            ttk.Entry(win, textvariable=v_kraenz, width=6).grid(row=r, column=4, padx=4, pady=3)
            eingaben[p] = (v_punkte, v_pumpen, v_neuner, v_kraenz)

        result = {}

        def parse_int(s):
            try:
                return int((s or "0").strip())
            except Exception:
                return 0

        def ok():
            for p, (vp, vpu, vn, vk) in eingaben.items():
                result[p] = {
                    "punkte":  parse_int(vp.get()),
                    "pumpen":  parse_int(vpu.get()),
                    "neuner":  parse_int(vn.get()),
                    "kraenze": parse_int(vk.get()),
                }
            win.destroy()

        # Wenn Fenster über das "X" geschlossen wird -> alles 0, aber gültige Keys
        def on_close():
            for p in teilnehmer:
                if p not in result:
                    result[p] = {"punkte": 0, "pumpen": 0, "neuner": 0, "kraenze": 0}
            win.destroy()

        win.protocol("WM_DELETE_WINDOW", on_close)
        ttk.Button(win, text="OK", command=ok).grid(row=len(teilnehmer)+1, column=0, columnspan=5, pady=8)
        self.root.wait_window(win)

        # Sicherheitsnetz (falls aus irgendeinem Grund noch etwas fehlt)
        for p in teilnehmer:
            result.setdefault(p, {"punkte": 0, "pumpen": 0, "neuner": 0, "kraenze": 0})

        return result

    def _add_tiebreak_stats(self, player, pu=0, nn=0, kk=0, pts=0):
        """
        Summiert Stech-Würfe auf, damit sie bei der Abrechnung mitgezählt werden.
        - pu  = Pumpen
        - nn  = Neuner
        - kk  = Kränze
        - pts = Stech-Punkte (werden nur zur Info gespeichert, NICHT zur Spielsumme addiert)
        """
        if not hasattr(self, "tiebreak_extras") or self.tiebreak_extras is None:
            self.tiebreak_extras = {}

        if player not in self.tiebreak_extras:
            self.tiebreak_extras[player] = {"pumpen": 0, "neuner": 0, "kranz": 0, "punkte": 0}

        self.tiebreak_extras[player]["pumpen"] += int(pu or 0)
        self.tiebreak_extras[player]["neuner"] += int(nn or 0)
        self.tiebreak_extras[player]["kranz"]  += int(kk or 0)
        self.tiebreak_extras[player]["punkte"] += int(pts or 0)

    def run_stechen(self, teilnehmer, art="punkte"):
        """
        Stechen:
        - Eingabe Punkte/Pumpen/Neuner/Kränze je Runde
        - Bei Gleichstand: weitere Runde nur für die Gleichstehenden
        - Es wird NUR gesammelt (self.tiebreak_extras); keine Kassenbuchungen hier.
        Rückgabe: Reihenfolge (Sieger -> Letzter)
        """
        teilnehmer = list(teilnehmer)
        if len(teilnehmer) < 2:
            return teilnehmer

        def get_int(d, key):
            try:
                return int(d.get(key, 0) or 0)
            except Exception:
                return 0

        kum_punkte = {p: 0 for p in teilnehmer}
        remaining   = teilnehmer[:]
        final_order = []

        while remaining:
            runde = self._stechen_runde_dialog(remaining, art=art) or {}

            # Stech-Würfe sammeln (für Abrechnung/Anzeige) und Punkte kumulieren
            for p in list(remaining):
                pdata = runde.get(p, {})  # durch den Dialog sollten Keys da sein; vorsichtshalber .get()
                pu  = get_int(pdata, "pumpen")
                nn  = get_int(pdata, "neuner")
                kk  = get_int(pdata, "kraenze")
                pts = get_int(pdata, "punkte")

                self._add_tiebreak_stats(p, pu=pu, nn=nn, kk=kk, pts=pts)
                kum_punkte[p] += pts

            max_pts = max(kum_punkte[p] for p in remaining)
            leaders = [p for p in remaining if kum_punkte[p] == max_pts]

            if len(leaders) == 1:
                sieger = leaders[0]
                final_order.append(sieger)
                remaining.remove(sieger)
                if remaining and len(remaining) == 1:
                    final_order.append(remaining[0])
                    remaining.clear()
            else:
                andere    = [p for p in remaining if p not in leaders]
                remaining = leaders + andere

            if not remaining:
                break

            if len(remaining) == 2 and kum_punkte[remaining[0]] != kum_punkte[remaining[1]]:
                final_order.extend(sorted(remaining, key=lambda p: kum_punkte[p], reverse=True))
                remaining.clear()

        # Fallback: falls irgendwer noch fehlt, hinten anhängen
        for p in teilnehmer:
            if p not in final_order:
                final_order.append(p)

        return final_order

    def resolve_points_tiebreak(self):
        """
        Ermittelt die finale Rangfolge VOR der Abrechnung.
        - Zuerst: Pumpen-Stechen unter den Spielern mit global meisten Pumpen (falls >1).
        - Dann: Für jede Punkte-Gruppe mit Gleichstand → Punkte-Stechen.
        Beide Stechen nutzen run_stechen() (3 Würfe + Sudden Death) und buchen Strafen sofort.
        """
        # --- Hilfswerte holen ---
        total_points = {p: sum(self.players[p].get("punkte", [0, 0, 0, 0])) for p in self.players}
        pump_counts  = {p: self.zusatzfelder[p]["Pumpen"].get() for p in self.players}

        # --- 1) Pumpen-Stechen (nur wenn mind. zwei den globalen Maximalwert haben) ---
        pump_rank = {}  # niedrigere Zahl = besser
        if pump_counts:
            max_pump = max(pump_counts.values())
            top_pumper = [p for p, v in pump_counts.items() if v == max_pump and max_pump > 0]
            if len(top_pumper) > 1:
                order_pump = self.run_stechen(top_pumper, art="pumpen")      # öffnet GUI, bucht Strafen
                pump_rank = {p: i for i, p in enumerate(order_pump)}         # Merke Reihenfolge für spätere Stability
            else:
                pump_rank = {}

        # --- 2) Gruppen nach Punkten, absteigend ---
        groups = {}
        for p, pts in total_points.items():
            groups.setdefault(pts, []).append(p)

        final_order = []
        for pts in sorted(groups.keys(), reverse=True):
            grp = groups[pts][:]
            if len(grp) == 1:
                final_order.append(grp[0])
                continue

            # Vor-Sortierung nach zuvor ermittelter Pumpen-Reihenfolge (nur kosmetisch/ stabil)
            grp.sort(key=lambda x: pump_rank.get(x, 999))

            # Punkte-Stechen für diese Gruppe
            order_pts = self.run_stechen(grp, art="punkte")   # öffnet GUI, bucht Strafen
            final_order.extend(order_pts)

        # Sicherstellen, dass alle Spieler enthalten sind (falls oben keine Gruppe >1 war)
        for p in self.players:
            if p not in final_order:
                final_order.append(p)

        return final_order

    # -------------------- Helfer --------------------
    def restore_players(self):
        # gesamte Mitglieder laden
        mit = DatenHandler.laden_mitglieder().get("players", {})
        # laufendes Spiel laden (nur Punkte übernehmen, nicht Spieler löschen)
        spiel = DatenHandler.laden_spiel()
        sp_players = spiel.get("players", {})
        for p, d in mit.items():
            if p in sp_players:
                d["punkte"] = sp_players[p].get("punkte", [0, 0, 0, 0])
            else:
                d["punkte"] = d.get("punkte", [0, 0, 0, 0])
        self.players = mit
        DatenHandler.speichern_mitglieder(self.players)

    def lade_letzte_reihenfolge(self):
        """
        Liefert die zuletzt verwendete Spielerreihenfolge.
        1) Aus der Historie (jüngster Eintrag)
        2) Falls nicht vorhanden: aus dem laufenden Spiel (AKTUELLES_SPIEL)
        3) Fallback: alphabetisch nach aktuellem self.players
        """
        # 1) Historie (jüngster Eintrag)
        try:
            historie = DatenHandler._safe_read_json(HISTORIE_FILE, [])
            if historie:
                # nach Datum sortieren (dd.mm.yyyy)
                def _to_dt(e):
                    from datetime import datetime
                    try:
                        return datetime.strptime(e.get("datum", "01.01.1900"), "%d.%m.%Y")
                    except Exception:
                        return datetime.min
                historie_sorted = sorted(historie, key=_to_dt, reverse=True)
                last = historie_sorted[0]
                order = last.get("spieler_reihenfolge")
                if order and isinstance(order, list) and len(order) > 0:
                    return order
        except Exception:
            pass

        # 2) laufendes Spiel
        try:
            spiel = DatenHandler.laden_spiel()
            order = spiel.get("spieler_reihenfolge")
            if order and isinstance(order, list) and len(order) > 0:
                return order
            if "players" in spiel and spiel["players"]:
                return list(spiel["players"].keys())
        except Exception:
            pass

        # 3) Fallback: alphabetisch nach aktuellen Spielern
        return sorted(list(self.players.keys()))

    def save_results(self):
        data = {"players": self.players, "kasse": self.kasse.kasse}
        try:
            with open(DATA_FILE, "w") as f:
                json.dump(data, f, indent=4)
        except Exception as e:
            messagebox.showerror("Fehler", f"Speichern fehlgeschlagen: {e}")

    def on_close(self):
        # Mitgliederstände (offene Zahlungen etc.) sichern
        mit = DatenHandler.laden_mitglieder().get("players", {})
        for p, d in self.players.items():
            mit[p] = {**mit.get(p, {}), **d}
        DatenHandler.speichern_mitglieder(mit)

        # Laufenden UI-Stand als Snapshot sichern (falls nicht abgerechnet)
        self.save_runtime_snapshot()

        # Gesamtdaten (OPTIONAL: bleibt wie gehabt)
        self.save_results()

        self.root.destroy()

    def show_placement_table(self, final_order):
        """
        Zeigt ein modales Fenster mit der finalen Rangfolge (Platz, Spieler, Punkte, Pumpen).
        Pumpen aus dem Stechen (self.tiebreak_extras) werden zur Anzeige addiert.
        Die zwei Spieler mit den meisten (gesamt) Pumpen werden blau markiert.
        """
        # Hilfszugriff auf Stech-Extras
        extras = getattr(self, "tiebreak_extras", {})

        # Daten vorbereiten (Punkte = reguläre Summe; Pumpen = regulär + Stech-Extras)
        placement_data = []
        for rank, player in enumerate(final_order, start=1):
            punkte_reg = sum(self.players[player].get("punkte", [0, 0, 0, 0]))
            pumpen_reg = self.zusatzfelder[player]["Pumpen"].get() if player in self.zusatzfelder else 0
            pumpen_stechen = extras.get(player, {}).get("pumpen", 0)
            pumpen_total = pumpen_reg + pumpen_stechen

            placement_data.append((rank, player, punkte_reg, pumpen_total))

        # Top-2 bei (gesamt) Pumpen bestimmen
        pump_counts_total = {
            p: (self.zusatzfelder[p]["Pumpen"].get() if p in self.zusatzfelder else 0)
            + extras.get(p, {}).get("pumpen", 0)
            for p in self.players
        }
        top_two = [name for name, _ in sorted(pump_counts_total.items(),
                                            key=lambda x: x[1], reverse=True)[:2]]

        # Fenster bauen
        win = tk.Toplevel(self.root)
        win.title("Finale Platzierung")
        win.grab_set()

        tree = ttk.Treeview(win, columns=("Platz", "Spieler", "Punkte", "Pumpen"),
                            show="headings", height=min(12, len(final_order) + 1))
        tree.heading("Platz", text="Platz")
        tree.heading("Spieler", text="Spieler")
        tree.heading("Punkte", text="Punkte")
        tree.heading("Pumpen", text="Pumpen")
        tree.column("Platz", width=60, anchor="center")
        tree.column("Spieler", width=140, anchor="w")
        tree.column("Punkte", width=80, anchor="center")
        tree.column("Pumpen", width=80, anchor="center")
        tree.tag_configure("topPump", background="lightblue")
        tree.pack(fill="both", expand=True, padx=10, pady=10)

        for rank, player, punkte_reg, pumpen_total in placement_data:
            tags = ("topPump",) if player in top_two else ()
            tree.insert("", "end", values=(rank, player, punkte_reg, pumpen_total), tags=tags)

        ttk.Button(win, text="OK", command=win.destroy).pack(pady=8)
        self.root.wait_window(win)

    def _stechen_count(self, player, key):
        return (self.tiebreak_extras.get(player) or {}).get(key, 0)
    
    def _snapshot_has_content(self, snap_players: dict) -> bool:
        """True, wenn im Snapshot überhaupt Eingaben vorliegen (Rundenpunkte oder Zusatzfelder)."""
        for p, d in (snap_players or {}).items():
            punkte = d.get("punkte", [])
            if any(str(x).strip() not in ("", "0") for x in punkte):
                return True
            if d.get("pumpen", 0) or d.get("neuner", 0) or d.get("kranz", 0):
                return True
        return False

    def save_runtime_snapshot(self):
        """
        Speichert den aktuellen UI-Stand (Runden 1–4 + Pumpen/Neuner/Kranz) in AKTUELLES_SPIEL,
        damit beim nächsten Start alles wieder da ist, wenn noch nicht abgerechnet wurde.
        """
        try:
            snap_players = {}
            for player, entry_list in self.punkte_entries.items():
                # Rundenwerte aus den vier Entries lesen
                runden = []
                for e in entry_list[:-1]:  # letztes ist Summenlabel
                    try:
                        val = e.get().strip()
                        runden.append(int(val) if val else 0)
                    except Exception:
                        runden.append(0)

                # Zusatzfelder sicher lesen (0 als Default)
                pu = int(self.zusatzfelder.get(player, {}).get("Pumpen", tk.IntVar(value=0)).get()
                        if player in self.zusatzfelder else 0)
                nn = int(self.zusatzfelder.get(player, {}).get("Neuner", tk.IntVar(value=0)).get()
                        if player in self.zusatzfelder else 0)
                kr = int(self.zusatzfelder.get(player, {}).get("Kranz",  tk.IntVar(value=0)).get()
                        if player in self.zusatzfelder else 0)

                # Typ & offene Zahlung aus Mitgliedern ziehen (falls vorhanden)
                mit = DatenHandler.laden_mitglieder().get("players", {})
                typ  = (mit.get(player, {}) or {}).get("typ", self.players.get(player, {}).get("typ", "Stamm"))
                offen = float((mit.get(player, {}) or {}).get("offene_zahlung",
                            self.players.get(player, {}).get("offene_zahlung", 0.0)))

                snap_players[player] = {
                    "typ": typ,
                    "punkte": runden[:4] if len(runden) >= 4 else [0, 0, 0, 0],
                    "offene_zahlung": offen,
                    "pumpen": pu,
                    "neuner": nn,
                    "kranz": kr
                }

            snapshot = {
                "players": snap_players,
                "runde": 1,
                "abgerechnet": False
            }

            # Nur speichern, wenn überhaupt relevante Eingaben existieren (oder Spieler angelegt sind)
            if snap_players and self._snapshot_has_content(snap_players):
                DatenHandler.speichern_spiel(snapshot)
            else:
                # Keine Inhalte → Datei auf "kein aktives Spiel" setzen
                DatenHandler.speichern_spiel({"players": {}, "runde": 0, "abgerechnet": False})
        except Exception:
            # Wir wollen hier niemals crashen, wenn die GUI tippt
            pass

    def load_runtime_snapshot(self):
        """
        Lädt AKTUELLES_SPIEL und befüllt die GUI (Punktefelder & Zusatzfelder).
        Wird benutzt beim Start der App – nur wenn nicht abgerechnet.
        """
        try:
            snap = DatenHandler.laden_spiel()
            if not snap or snap.get("abgerechnet"):
                return
            snap_players = snap.get("players", {})
            if not snap_players:
                return

            # Spielerreihenfolge/Set für die GUI übernehmen
            # (Typ & offene Zahlung aus Mitgliederdatei priorisieren)
            mit = DatenHandler.laden_mitglieder().get("players", {})
            self.players = {}
            for name, d in snap_players.items():
                base = mit.get(name, {})
                self.players[name] = {
                    "typ": base.get("typ", d.get("typ", "Stamm")),
                    "punkte": d.get("punkte", [0, 0, 0, 0]),
                    "offene_zahlung": float(base.get("offene_zahlung", d.get("offene_zahlung", 0.0)))
                }

            # GUI neu aufbauen und danach Werte setzen
            self.create_punkteingabe()

            for name, d in snap_players.items():
                # Rundenpunkte in die 4 Entries schreiben + Summe aktualisieren
                punkte = d.get("punkte", [0, 0, 0, 0])[:4]
                if name in self.punkte_entries:
                    for i in range(4):
                        try:
                            self.punkte_entries[name][i].delete(0, tk.END)
                            self.punkte_entries[name][i].insert(0, str(punkte[i]))
                        except Exception:
                            pass
                    # Summe label
                    try:
                        self.punkte_entries[name][-1].config(text=str(sum(punkte)))
                    except Exception:
                        pass

                # Zusatzfelder (IntVar) setzen, falls vorhanden
                if name in self.zusatzfelder:
                    try: self.zusatzfelder[name]["Pumpen"].set(int(d.get("pumpen", 0)))
                    except Exception: pass
                    try: self.zusatzfelder[name]["Neuner"].set(int(d.get("neuner", 0)))
                    except Exception: pass
                    try: self.zusatzfelder[name]["Kranz"].set(int(d.get("kranz", 0)))
                    except Exception: pass

            # nach dem Befüllen einmal speichern (konsistenter Stand)
            self.save_runtime_snapshot()
        except Exception:
            pass
    
    def _build_tab_order(self):
        """Tab-Reihenfolge vertikal pro Runde: R1 alle Spieler, dann R2 alle Spieler, ..."""
        if not hasattr(self, "round_entries"):
            return
        self.tab_order = []
        self.entry_index = {}
        idx = 0
        for r in range(4):  # Runde 1..4
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
                # Tab / Shift+Tab abfangen
                w.bind("<Tab>", self._on_tab_key)
                w.bind("<ISO_Left_Tab>", self._on_shift_tab_key)  # mac / linux
                w.bind("<Shift-Tab>", self._on_shift_tab_key)     # windows
                idx += 1


    def _on_tab_key(self, event):
        """Vorwärts springen in unserer eigenen Reihenfolge."""
        if not getattr(self, "tab_order", None):
            return
        i = self.entry_index.get(event.widget, 0)
        nxt = (i + 1) % len(self.tab_order)  # nach letzter Zelle wieder zum Anfang
        self.tab_order[nxt].focus_set()
        return "break"  # Default-Tabbing unterdrücken


    def _on_shift_tab_key(self, event):
        """Rückwärts springen (Shift+Tab)."""
        if not getattr(self, "tab_order", None):
            return
        i = self.entry_index.get(event.widget, 0)
        prv = (i - 1) % len(self.tab_order)
        self.tab_order[prv].focus_set()
        return "break"

# -------------------- Start --------------------
if __name__ == "__main__":
    root = tk.Tk()
    setup_styles()
    app = KegelBruederApp(root)
    root.mainloop()
