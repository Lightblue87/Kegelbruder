import logging
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP

from database import get_connection


# =============================================================================
# Kassen-Logik (SQLite)
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
            "Transaktionen": [],
            "Letzte_Startgebuehren": 0.0,
        }
        self.lade_kasse()

    def get_bahngebuehr(self) -> float:
        """Robuster Zugriff – unterstützt auch alte Schlüssel/Schreibweisen."""
        return float(
            self.kasse.get("Bahngebühr")
            or self.kasse.get("Bahngebuehr")
            or self.kasse.get("Bahngebühr")
            or 0
        )

    def lade_kasse(self):
        """Lädt Kassendaten aus kasse_einstellungen + transaktionen."""
        conn = get_connection()
        rows = conn.execute(
            "SELECT schluessel, wert FROM kasse_einstellungen"
        ).fetchall()
        for row in rows:
            self.kasse[row["schluessel"]] = row["wert"]

        # Transaktionen laden (letzte 200)
        tx_rows = conn.execute(
            "SELECT text FROM transaktionen ORDER BY id DESC LIMIT 200"
        ).fetchall()
        # Umgekehrt, damit neueste am Ende steht
        self.kasse["Transaktionen"] = [r["text"] for r in reversed(tx_rows)]

    def speichere_kasse(self):
        """Schreibt Kassendaten in kasse_einstellungen + transaktionen."""
        conn = get_connection()
        try:
            felder = [
                "Startgeld", "Pumpe", "Neuner", "Kranz",
                "Strafe Stamm", "Bahngebühr", "Kassenstand", "Letzte_Startgebuehren"
            ]
            for key in felder:
                if key in self.kasse:
                    conn.execute(
                        "INSERT OR REPLACE INTO kasse_einstellungen (schluessel, wert) VALUES (?, ?)",
                        (key, float(self.kasse[key])),
                    )

            # Transaktionen komplett ersetzen
            conn.execute("DELETE FROM transaktionen")
            for tx in self.kasse.get("Transaktionen", []):
                conn.execute(
                    "INSERT INTO transaktionen (text) VALUES (?)", (tx,)
                )
            conn.commit()
        except Exception as e:
            conn.rollback()
            logging.error(f"Speichern Kasse fehlgeschlagen: {e}")

    def aktualisiere_kasse(self, players):
        total = self.kasse["Startgeld"] * len(players)
        self.kasse["Letzte_Startgebuehren"] = total
        self.speichere_kasse()

    def anpassen_gebuehren(self, kategorie, betrag):
        if betrag < 0:
            logging.warning(f"Negativer Betrag für {kategorie}: {betrag}")
            return False
        if kategorie in self.kasse and isinstance(betrag, (int, float)) and betrag >= 0:
            self.kasse[kategorie] = float(betrag)
            self.speichere_kasse()
            return True
        return False

    def einzahlung(self, betrag, beschreibung="Manuelle Einzahlung"):
        if betrag < 0:
            logging.warning(f"Negative Einzahlung verweigert: {betrag}")
            return False
        if betrag <= 0:
            return False

        datum = datetime.now().strftime("%d.%m.%Y")
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
        if betrag < 0:
            logging.warning(f"Negative Auszahlung verweigert: {betrag}")
            return False
        if 0 < betrag <= self.kasse["Kassenstand"]:
            datum = datetime.now().strftime("%d.%m.%Y")
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
