"""
gui/player_management.py – Spielerverwaltungsfenster

Erlaubt das Hinzufügen, Bearbeiten und Entfernen von Stamm- und Gastspielern.

Kein Rück-Verweis auf KegelBruederApp nötig – alle Widget-Referenzen
(player_listbox) und Callbacks bleiben lokal in dieser Klasse.
Der Aufrufer übergibt nur das Tk-Root-Fenster als Parent.
"""

import tkinter as tk
from tkinter import messagebox, ttk

from data_handler import DatenHandler


class PlayerManagementWindow:
    """Spielerverwaltungsfenster – öffnet sich als Toplevel."""

    def __init__(self, root: tk.Misc):
        self.root = root
        self.win  = tk.Toplevel(root)
        self.win.title("Spieler verwalten")
        self.player_listbox: tk.Listbox = None
        self._build()

    def _build(self):
        win = self.win

        self.player_listbox = tk.Listbox(win, height=10, width=50)
        self.player_listbox.grid(row=0, column=0, padx=10, pady=5, columnspan=3, sticky="ew")
        self._refresh_list()

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
            self._refresh_list()
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
                    self._refresh_list()

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
                if new_name != selected and new_name in mit["players"]:
                    messagebox.showerror(
                        "Fehler",
                        f"Ein Spieler mit dem Namen '{new_name}' existiert bereits.\n"
                        "Bitte einen anderen Namen wählen."
                    )
                    return
                if new_name != selected:
                    mit["players"][new_name] = mit["players"].pop(selected)
                mit["players"][new_name]["typ"] = new_typ
                if new_typ == "Stamm":
                    mit["players"][new_name]["offene_zahlung"] = _parse_money(offen_edit_var.get())
                else:
                    mit["players"][new_name]["offene_zahlung"] = 0.0
                DatenHandler.speichern_mitglieder(mit["players"])
                self._refresh_list()
                ew.destroy()

            ttk.Button(ew, text="Speichern", command=save_edit).grid(row=3, column=0, columnspan=3, pady=8)

        ttk.Button(win, text="Hinzufügen", command=add_player).grid(row=4, column=0, pady=8)
        ttk.Button(win, text="Entfernen",  command=remove_player).grid(row=4, column=1, pady=8)
        ttk.Button(win, text="Bearbeiten", command=edit_player).grid(row=4, column=2, pady=8)

    def _refresh_list(self):
        """Aktualisiert die Spielerliste aus der Mitgliederdatei."""
        self.player_listbox.delete(0, tk.END)
        mit = DatenHandler.laden_mitglieder().get("players", {})
        for p, d in sorted(mit.items()):
            self.player_listbox.insert(tk.END, f"{p} ({d['typ']})")
