"""
gui/archive.py – Archivansicht (Spielhistorie)

Zeigt abgeschlossene Spieltage an: Datum, Spieleranzahl, Transaktionen,
finale Platzierung und Einzeltransaktionen.

Kein Rück-Verweis auf KegelBruederApp nötig – reine Leseansicht.
Der Aufrufer übergibt nur das Tk-Root-Fenster als Parent.
"""

import tkinter as tk
from datetime import datetime
from tkinter import ttk

from data_handler import DatenHandler


class ArchiveWindow:
    """Öffnet ein eigenständiges Toplevel-Fenster mit der Spielhistorie."""

    def __init__(self, root: tk.Misc):
        win = tk.Toplevel(root)
        win.title("Archiv")
        win.geometry("800x600")

        data = DatenHandler.laden_historie()

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
