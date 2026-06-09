"""
gui/billing.py – Abrechnungsfenster, Strafberechnung, Stechen/Tie-Break, Spielabschluss

Enthält:
  BillingWindow   – Abrechnung anzeigen und speichern
  Tiebreak-Logik  – run_stechen, resolve_points_tiebreak, _stechen_runde_dialog
  show_placement_table – Ergebnisanzeige

Bugfixes hier:
  - Bahngebühr-Lookup nutzt jetzt kasse.get_bahngebuehr() statt fehleranfälligem
    manuellen key-Suchen mit zwei Schlüssel-Varianten.
  - Doppelter Session-Reset (session_reset + _session_tx = []) in abrechnung_speichern
    ist auf einen einzigen Aufruf reduziert.
  - berechne_strafen_anteile (identische Kopie von berechne_abrechnung, nie aufgerufen)
    wurde entfernt.
"""

import logging
import tkinter as tk
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP
from tkinter import messagebox, ttk

from data_handler import DatenHandler


class BillingWindow:
    """Abrechnungsfenster: zeigt Plätze, Kosten, Zahlungsfelder und führt Abschluss durch."""

    def __init__(self, app):
        self.app  = app
        self.win:               tk.Toplevel = None
        self.abrechnung_entries: dict       = {}
        self.spenden_labels:     dict       = {}

    # ------------------------------------------------------------------
    def open(self):
        """Öffnet das Abrechnungsfenster (oder bricht das Spiel ab, wenn keine Punkte)."""
        def _hat_irgendwer_punkte():
            for p, entries in self.app.punkte_entries.items():
                runden = [e.get().strip() for e in entries[:-1]]
                if any(val != "" for val in runden):
                    return True
            return False

        if not _hat_irgendwer_punkte():
            messagebox.showinfo(
                "Keine Rundenpunkte",
                "Es wurden in den Feldern 'Runde 1' bis 'Runde 4' keine Punkte eingegeben.\n"
                "Das Spiel wird abgebrochen."
            )
            self.app.abort_game(silent=True)
            return

        final_order   = self._resolve_points_tiebreak()
        spieler_kosten = self._berechne_abrechnung()

        data = []
        for platz, spieler in enumerate(final_order, start=1):
            punkte_reg = sum(self.app.players[spieler].get("punkte", [0, 0, 0, 0]))
            data.append((platz, spieler, float(spieler_kosten.get(spieler, 0.0)), punkte_reg))
        data.sort(key=lambda x: x[0], reverse=True)

        self.win = tk.Toplevel(self.app.root)
        self.win.title("Spielerabrechnung")

        headers = ["Platz", "Spieler", "Zu zahlen (€)", "Gezahlt (€)", "Spende (€)", "Punkte"]
        for i, header in enumerate(headers):
            ttk.Label(self.win, text=header, font=("Arial", 10, "bold")
                      ).grid(row=0, column=i, padx=5, pady=5, sticky="ew")

        def berechne_spende_zeile(player, gezahlt_var, spende_var, zu_zahlen):
            try:
                gez = float((gezahlt_var.get() or "0").replace(",", "."))
            except ValueError:
                gez = 0.0
            # FIX #8: Decimal-Arithmetik
            gez_dec       = Decimal(str(gez)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
            zu_zahlen_dec = Decimal(str(zu_zahlen)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
            sp = max(Decimal('0.00'), gez_dec - zu_zahlen_dec)
            spende_var.set(f"{sp:.2f} €")

        row = 1
        for platz, spieler, kosten, punkte_reg in data:
            ttk.Label(self.win, text=str(platz)).grid(row=row, column=0, padx=5, pady=5, sticky="w")
            ttk.Label(self.win, text=spieler).grid(row=row, column=1, padx=5, pady=5, sticky="w")
            ttk.Label(self.win, text=f"{kosten:.2f} €").grid(row=row, column=2, padx=5, pady=5, sticky="ew")

            gezahlt_var   = tk.StringVar(value="0,00")
            gezahlt_entry = ttk.Entry(self.win, textvariable=gezahlt_var, width=10)
            gezahlt_entry.grid(row=row, column=3, padx=5, pady=5, sticky="ew")

            spende_var = tk.StringVar(value="0,00")
            ttk.Label(self.win, textvariable=spende_var, foreground="green"
                      ).grid(row=row, column=4, padx=5, pady=5, sticky="ew")

            ttk.Label(self.win, text=str(punkte_reg)).grid(row=row, column=5, padx=5, pady=5, sticky="w")

            gezahlt_entry.bind(
                "<FocusOut>",
                lambda e, p=spieler, g=gezahlt_var, s=spende_var, z=kosten:
                    berechne_spende_zeile(p, g, s, z)
            )
            self.abrechnung_entries[spieler] = (kosten, gezahlt_var)
            self.spenden_labels[spieler]      = spende_var
            row += 1

        ttk.Button(self.win, text="Abrechnen",
                   command=self._abrechnung_speichern
                   ).grid(row=row, column=0, columnspan=len(headers), pady=10)

    # ------------------------------------------------------------------
    def _berechne_abrechnung(self) -> dict:
        """Liefert pro Spieler den zu zahlenden Strafbetrag (reine Berechnung)."""
        kosten       = {p: 0.0 for p in self.app.players}
        preis_pumpe  = float(self.app.kasse.kasse["Pumpe"])
        preis_neuner = float(self.app.kasse.kasse["Neuner"])
        preis_kranz  = float(self.app.kasse.kasse["Kranz"])

        counts = {}
        for p in self.app.players:
            if p not in self.app.zusatzfelder:
                logging.warning(f"Spieler {p} nicht in zusatzfelder, skippe")
                counts[p] = (0, 0, 0)
                continue
            pumpen_anz = int(self.app.zusatzfelder[p]["Pumpen"].get()) + self._stechen_count(p, "pumpen")
            neuner_anz = int(self.app.zusatzfelder[p]["Neuner"].get()) + self._stechen_count(p, "neuner")
            kranz_anz  = int(self.app.zusatzfelder[p]["Kranz"].get())  + self._stechen_count(p, "kranz")
            counts[p]  = (pumpen_anz, neuner_anz, kranz_anz)

        for p, (pumpen_anz, _, _) in counts.items():
            kosten[p] += pumpen_anz * preis_pumpe

        for werfer, (_, neuner_anz, kranz_anz) in counts.items():
            aufschlag = neuner_anz * preis_neuner + kranz_anz * preis_kranz
            if aufschlag <= 0:
                continue
            for zahler in self.app.players:
                if zahler == werfer:
                    continue
                kosten[zahler] += aufschlag

        return kosten

    # ------------------------------------------------------------------
    def _abrechnung_speichern(self):
        """Verbucht Strafen, Spenden, Bahngebühr und schließt das Spielgeschehen."""
        datum = datetime.now().strftime("%d.%m.%Y")
        archive_start_index = len(self.app.kasse.kasse.get("Transaktionen", []))

        tiebreak = getattr(self.app, "tiebreak_extras", {}) or {}

        def stechen_count(player, key):
            return (tiebreak.get(player) or {}).get(key, 0)

        preis_pumpe  = float(self.app.kasse.kasse.get("Pumpe", 0))
        preis_neuner = float(self.app.kasse.kasse.get("Neuner", 0))
        preis_kranz  = float(self.app.kasse.kasse.get("Kranz", 0))

        counts = {}
        for p in self.app.players:
            if p not in self.app.zusatzfelder:
                counts[p] = (0, 0, 0)
                continue
            pumpen_anz = int(self.app.zusatzfelder[p]["Pumpen"].get()) + stechen_count(p, "pumpen")
            neuner_anz = int(self.app.zusatzfelder[p]["Neuner"].get()) + stechen_count(p, "neuner")
            kranz_anz  = int(self.app.zusatzfelder[p]["Kranz"].get())  + stechen_count(p, "kranz")
            counts[p]  = (pumpen_anz, neuner_anz, kranz_anz)

        kosten = {p: 0.0 for p in self.app.players}
        for p, (pumpen_anz, _, _) in counts.items():
            kosten[p] += pumpen_anz * preis_pumpe
        for werfer, (_, neuner_anz, kranz_anz) in counts.items():
            aufschlag = neuner_anz * preis_neuner + kranz_anz * preis_kranz
            if aufschlag <= 0:
                continue
            for zahler in self.app.players:
                if zahler == werfer:
                    continue
                kosten[zahler] += aufschlag

        startgeld_info = float(self.app.kasse.kasse.get("Letzte_Startgebuehren", 0.0) or 0.0)
        if startgeld_info > 0:
            self.app.kasse.kasse["Transaktionen"].append(
                f"{datum} | {startgeld_info:.2f}€: Startgelder für {len(self.app.players)} Spieler"
            )
            self.app.kasse.speichere_kasse()

        mitglieder = DatenHandler.laden_mitglieder().get("players", {})
        gesamt_zahlungen = 0.0

        for player, betrag in kosten.items():
            betrag = round(float(betrag), 2)
            player_data = dict(mitglieder.get(player, self.app.players.get(player, {})))
            player_data.setdefault("typ", self.app.players.get(player, {}).get("typ", "Stamm"))
            player_data.setdefault("punkte", self.app.players.get(player, {}).get("punkte", [0, 0, 0, 0]))
            player_data["offene_zahlung"] = float(player_data.get("offene_zahlung", 0.0))

            if betrag > 0:
                player_data["offene_zahlung"] = round(player_data["offene_zahlung"] + betrag, 2)
                self.app.kasse.kasse["Transaktionen"].append(
                    f"{datum} | {betrag:.2f}€: {datum} - Strafe belastet: {player}"
                )

            _, gezahlt_var = self.abrechnung_entries.get(player, (betrag, None))
            try:
                gezahlt = float((gezahlt_var.get() if gezahlt_var else "0").replace(",", "."))
            except Exception:
                gezahlt = 0.0
            gezahlt = max(0.0, round(float(gezahlt), 2))

            zahlung_auf_schuld = min(gezahlt, player_data["offene_zahlung"])
            if zahlung_auf_schuld > 0:
                player_data["offene_zahlung"] = round(
                    max(0.0, player_data["offene_zahlung"] - zahlung_auf_schuld), 2
                )
                self.app._session_einzahlung(zahlung_auf_schuld, f"{datum} - Zahlung von {player}")
                gesamt_zahlungen += zahlung_auf_schuld

            spende = round(max(0.0, gezahlt - zahlung_auf_schuld), 2)
            if spende > 0:
                self.app._session_einzahlung(spende, f"{datum} - Spende von {player}")
                gesamt_zahlungen += spende

            mitglieder[player] = player_data
            if player in self.app.players:
                self.app.players[player]["offene_zahlung"] = player_data["offene_zahlung"]

        DatenHandler.speichern_mitglieder(mitglieder)
        self.app.kasse.speichere_kasse()

        # FIX: get_bahngebuehr() statt manueller key-Suche mit zwei Varianten
        bahn = self.app.kasse.get_bahngebuehr()
        if bahn > 0:
            self.app._session_auszahlung(bahn, f"{datum} - Bahngebühr")

        info_summe = round(gesamt_zahlungen + startgeld_info, 2)
        if info_summe > 0:
            self.app.kasse.einzahlung(info_summe, f"{datum} - Einnahmen vom Spieltag")

        # Kassenverwaltungsfenster aktualisieren (falls geöffnet)
        self.app.refresh_kassen_gui()

        try:
            archivierte_spieler = {p: self.app.players[p] for p in self.app.players}
            spieltag_transaktionen = list(
                self.app.kasse.kasse.get("Transaktionen", [])[archive_start_index:]
            )
            DatenHandler.archivieren_spiel({
                "datum":        datum,
                "players":      archivierte_spieler,
                "transaktionen": spieltag_transaktionen,
            })
        except Exception as e:
            logging.error(f"Fehler beim Archivieren: {e}")

        self.app.sperre_spielfelder()
        messagebox.showinfo(
            "Abrechnung",
            "Abrechnung gespeichert. Strafen, Spenden & Bahngebühr verbucht.\n"
            "Alle Felder gesperrt – starte ein neues Spiel, um fortzufahren."
        )

        DatenHandler.speichern_spiel({"players": {}, "runde": 1})
        if self.win and self.win.winfo_exists():
            self.win.destroy()

        self.app.tiebreak_extras = {}
        # FIX: doppelter Reset entfernt – _session_reset() genügt
        self.app._session_reset()
        self.app._pre_session_schulden = {}

    # ------------------------------------------------------------------
    # Tiebreak / Stechen
    # ------------------------------------------------------------------
    def _stechen_runde_dialog(self, teilnehmer, art="punkte"):
        """Zeigt ein kleines Fenster für EINE Stechen-Runde."""
        win = tk.Toplevel(self.app.root)
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

        def on_close():
            for p in teilnehmer:
                if p not in result:
                    result[p] = {"punkte": 0, "pumpen": 0, "neuner": 0, "kraenze": 0}
            win.destroy()

        win.protocol("WM_DELETE_WINDOW", on_close)
        ttk.Button(win, text="OK", command=ok).grid(row=len(teilnehmer) + 1, column=0, columnspan=5, pady=8)
        self.app.root.wait_window(win)

        for p in teilnehmer:
            result.setdefault(p, {"punkte": 0, "pumpen": 0, "neuner": 0, "kraenze": 0})
        return result

    def _add_tiebreak_stats(self, player, pu=0, nn=0, kk=0, pts=0):
        """Akkumuliert Stechen-Würfe in app.tiebreak_extras."""
        if not hasattr(self.app, "tiebreak_extras") or self.app.tiebreak_extras is None:
            self.app.tiebreak_extras = {}
        if player not in self.app.tiebreak_extras:
            self.app.tiebreak_extras[player] = {"pumpen": 0, "neuner": 0, "kranz": 0, "punkte": 0}
        self.app.tiebreak_extras[player]["pumpen"] += int(pu  or 0)
        self.app.tiebreak_extras[player]["neuner"] += int(nn  or 0)
        self.app.tiebreak_extras[player]["kranz"]  += int(kk  or 0)
        self.app.tiebreak_extras[player]["punkte"] += int(pts or 0)

    def _stechen_count(self, player, key):
        return (getattr(self.app, "tiebreak_extras", {}) or {}).get(player, {}).get(key, 0)

    def run_stechen(self, teilnehmer, art="punkte"):
        """Stechen-Ablauf: wiederholt bis ein Sieger feststeht."""
        teilnehmer = list(teilnehmer)
        if len(teilnehmer) < 2:
            return teilnehmer

        def get_int(d, key):
            try:
                return int(d.get(key, 0) or 0)
            except Exception:
                return 0

        kum_punkte  = {p: 0 for p in teilnehmer}
        remaining   = teilnehmer[:]
        final_order = []

        while remaining:
            runde = self._stechen_runde_dialog(remaining, art=art) or {}
            for p in list(remaining):
                pdata = runde.get(p, {})
                pu  = get_int(pdata, "pumpen")
                nn  = get_int(pdata, "neuner")
                kk  = get_int(pdata, "kraenze")
                pts = get_int(pdata, "punkte")
                self._add_tiebreak_stats(p, pu=pu, nn=nn, kk=kk, pts=pts)
                kum_punkte[p] += pts

            if not remaining:   # Guard vor max() (FIX #2)
                break

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

        for p in teilnehmer:
            if p not in final_order:
                final_order.append(p)
        return final_order

    def _resolve_points_tiebreak(self):
        """Ermittelt die finale Rangfolge vor der Abrechnung."""
        total_points = {p: sum(self.app.players[p].get("punkte", [0, 0, 0, 0]))
                        for p in self.app.players}
        pump_counts  = {
            p: self.app.zusatzfelder[p]["Pumpen"].get() if p in self.app.zusatzfelder else 0
            for p in self.app.players
        }

        pump_rank = {}
        if pump_counts:
            pump_values = list(pump_counts.values())
            if pump_values:
                max_pump   = max(pump_values)
                top_pumper = [p for p, v in pump_counts.items() if v == max_pump and max_pump > 0]
                if len(top_pumper) > 1:
                    order_pump = self.run_stechen(top_pumper, art="pumpen")
                    pump_rank  = {p: i for i, p in enumerate(order_pump)}

        groups = {}
        for p, pts in total_points.items():
            groups.setdefault(pts, []).append(p)

        final_order = []
        for pts in sorted(groups.keys(), reverse=True):
            grp = groups[pts][:]
            if len(grp) == 1:
                final_order.append(grp[0])
                continue
            grp.sort(key=lambda x: pump_rank.get(x, 999))
            order_pts = self.run_stechen(grp, art="punkte")
            final_order.extend(order_pts)

        for p in self.app.players:
            if p not in final_order:
                final_order.append(p)
        return final_order

    # ------------------------------------------------------------------
    def show_placement_table(self, final_order):
        """Zeigt die finale Rangfolge in einem Treeview-Fenster."""
        extras = getattr(self.app, "tiebreak_extras", {})

        placement_data = []
        for rank, player in enumerate(final_order, start=1):
            punkte_reg     = sum(self.app.players[player].get("punkte", [0, 0, 0, 0]))
            pumpen_reg     = self.app.zusatzfelder[player]["Pumpen"].get() if player in self.app.zusatzfelder else 0
            pumpen_stechen = extras.get(player, {}).get("pumpen", 0)
            placement_data.append((rank, player, punkte_reg, pumpen_reg + pumpen_stechen))

        pump_counts_total = {
            p: (self.app.zusatzfelder[p]["Pumpen"].get() if p in self.app.zusatzfelder else 0)
               + extras.get(p, {}).get("pumpen", 0)
            for p in self.app.players
        }
        top_two = [name for name, _ in sorted(pump_counts_total.items(),
                                              key=lambda x: x[1], reverse=True)[:2]]

        win = tk.Toplevel(self.app.root)
        win.title("Finale Platzierung")
        win.grab_set()

        tree = ttk.Treeview(win, columns=("Platz", "Spieler", "Punkte", "Pumpen"),
                            show="headings", height=min(12, len(final_order) + 1))
        tree.heading("Platz",   text="Platz")
        tree.heading("Spieler", text="Spieler")
        tree.heading("Punkte",  text="Punkte")
        tree.heading("Pumpen",  text="Pumpen")
        tree.column("Platz",   width=60,  anchor="center")
        tree.column("Spieler", width=140, anchor="w")
        tree.column("Punkte",  width=80,  anchor="center")
        tree.column("Pumpen",  width=80,  anchor="center")
        tree.tag_configure("topPump", background="lightblue")
        tree.pack(fill="both", expand=True, padx=10, pady=10)

        for rank, player, punkte_reg, pumpen_total in placement_data:
            tags = ("topPump",) if player in top_two else ()
            tree.insert("", "end", values=(rank, player, punkte_reg, pumpen_total), tags=tags)

        ttk.Button(win, text="OK", command=win.destroy).pack(pady=8)
        self.app.root.wait_window(win)
