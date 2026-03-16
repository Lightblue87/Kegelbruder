import json
import logging
import os
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP

from config import DATA_FILE_KASSE
from storage import AtomicFileWriter


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
            self.kasse.get("Bahngebühr")
            or self.kasse.get("Bahngebuehr")
            or self.kasse.get("Bahngeb\u00fchr")
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
        for k, v in defaults.items():
            if k not in self.kasse:
                self.kasse[k] = v
                changed = True
        if not isinstance(self.kasse.get("Transaktionen", []), list):
            self.kasse["Transaktionen"] = []
            changed = True
        if changed:
            self.speichere_kasse()

    def speichere_kasse(self):
        try:
            AtomicFileWriter.atomic_write(DATA_FILE_KASSE, self.kasse)
        except Exception as e:
            logging.error(f"Speichern Kasse fehlgeschlagen: {e}")

    def aktualisiere_kasse(self, players):
        total = self.kasse["Startgeld"] * len(players)
        self.kasse["Letzte_Startgebuehren"] = total
        self.speichere_kasse()

    def anpassen_gebuehren(self, kategorie, betrag):
        # FIX: Input-Validierung
        if betrag < 0:
            logging.warning(f"Negativer Betrag für {kategorie}: {betrag}")
            return False

        if kategorie in self.kasse and isinstance(betrag, (int, float)) and betrag >= 0:
            self.kasse[kategorie] = float(betrag)
            self.speichere_kasse()
            return True
        return False

    def einzahlung(self, betrag, beschreibung="Manuelle Einzahlung"):
        """Fügt Geld zur Kasse hinzu und speichert die Transaktion.

        Hinweis: Das Reduzieren offener Spieler-Zahlungen obliegt dem Aufrufer
        (DatenHandler.reduziere_ausstehende_zahlung), nicht der Kasse selbst.
        """
        # FIX: Input-Validierung
        if betrag < 0:
            logging.warning(f"Negative Einzahlung verweigert: {betrag}")
            return False

        if betrag <= 0:
            return False

        datum = datetime.now().strftime("%d.%m.%Y")

        # FIX #8: Decimal-Arithmetik für Geldbeträge
        betrag_decimal = Decimal(str(betrag)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
        betrag = float(betrag_decimal)

        info_only = (
            "Einnahmen vom Spieltag" in beschreibung
            or "Startgelder für" in beschreibung
        )
        if info_only:
            self.kasse["Transaktionen"].append(f"{datum} | {betrag:.2f}€: {beschreibung}")
            self.speichere_kasse()
            return True

        self.kasse["Kassenstand"] += betrag
        self.kasse["Transaktionen"].append(f"{datum} | +{betrag:.2f}€: {beschreibung}")

        self.speichere_kasse()
        return True

    def auszahlung(self, betrag, beschreibung="Manuelle Auszahlung"):
        # FIX: Input-Validierung
        if betrag < 0:
            logging.warning(f"Negative Auszahlung verweigert: {betrag}")
            return False

        if 0 < betrag <= self.kasse["Kassenstand"]:
            datum = datetime.now().strftime("%d.%m.%Y")

            # FIX #8: Decimal-Arithmetik
            betrag_decimal = Decimal(str(betrag)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
            betrag = float(betrag_decimal)

            self.kasse["Kassenstand"] -= betrag
            self.kasse["Transaktionen"].append(f"{datum} | -{betrag:.2f}€: {beschreibung}")
            self.speichere_kasse()
            return True
        return False

    def get_kassenstand(self):
        return float(self.kasse["Kassenstand"])

    def zeige_transaktionen(self, limit=10):
        return self.kasse["Transaktionen"][-limit:]
