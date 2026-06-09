import json
import logging
import threading
from datetime import datetime

from database import get_connection


# =============================================================================
# Datenzugriff (SQLite)
# =============================================================================
class DatenHandler:
    _lock = threading.Lock()

    # ------------------------------------------------------------------
    # Mitglieder
    # ------------------------------------------------------------------

    @staticmethod
    def laden_mitglieder() -> dict:
        """Gibt {"players": {name: {typ, punkte, offene_zahlung}, ...}} zurück."""
        with DatenHandler._lock:
            conn = get_connection()
            rows = conn.execute(
                "SELECT name, typ, offene_zahlung FROM mitglieder"
            ).fetchall()
            players = {}
            for row in rows:
                players[row["name"]] = {
                    "typ": row["typ"],
                    "punkte": [0, 0, 0, 0],
                    "offene_zahlung": row["offene_zahlung"],
                }
            return {"players": players}

    @staticmethod
    def laden_mitglieder_dict() -> dict:
        """Gibt nur das innere players-Dict zurück."""
        return DatenHandler.laden_mitglieder()["players"]

    @staticmethod
    def speichern_mitglieder(players: dict):
        """Ersetzt alle Mitglieder-Einträge (INSERT OR REPLACE)."""
        with DatenHandler._lock:
            conn = get_connection()
            try:
                # Alle bestehenden entfernen, dann neu einfügen
                conn.execute("DELETE FROM mitglieder")
                for name, d in players.items():
                    conn.execute(
                        "INSERT INTO mitglieder (name, typ, offene_zahlung) VALUES (?, ?, ?)",
                        (
                            name,
                            d.get("typ", "Stamm"),
                            float(d.get("offene_zahlung", 0.0)),
                        ),
                    )
                conn.commit()
            except Exception as e:
                conn.rollback()
                logging.error(f"Speichern Mitglieder fehlgeschlagen: {e}")

    # ------------------------------------------------------------------
    # Ältere Kompatibilitätsmethode
    # ------------------------------------------------------------------

    @staticmethod
    def laden() -> dict:
        """Legacy-Methode: gibt {"players": {}, "kasse": {}} zurück."""
        mitglieder = DatenHandler.laden_mitglieder()
        return {"players": mitglieder["players"], "kasse": {}}

    # ------------------------------------------------------------------
    # Aktuelles Spiel
    # ------------------------------------------------------------------

    @staticmethod
    def laden_spiel() -> dict:
        """Lädt das laufende Spiel aus der Datenbank."""
        with DatenHandler._lock:
            conn = get_connection()

            # Spieler laden
            rows = conn.execute(
                "SELECT * FROM aktuelles_spiel_spieler ORDER BY position"
            ).fetchall()
            players = {}
            for row in rows:
                players[row["name"]] = {
                    "typ": row["typ"],
                    "punkte": [
                        row["punkte_r1"],
                        row["punkte_r2"],
                        row["punkte_r3"],
                        row["punkte_r4"],
                    ],
                    "pumpen": row["pumpen"],
                    "neuner": row["neuner"],
                    "kranz": row["kranz"],
                    "position": row["position"],
                    "offene_zahlung": row["offene_zahlung"],
                }

            # Meta laden
            meta_rows = conn.execute(
                "SELECT schluessel, wert FROM aktuelles_spiel_meta"
            ).fetchall()
            meta = {r["schluessel"]: r["wert"] for r in meta_rows}

            runde = int(meta.get("runde", "0"))
            abgerechnet_raw = meta.get("abgerechnet", "false")
            abgerechnet = abgerechnet_raw.lower() == "true"
            spieler_reihenfolge_raw = meta.get("spieler_reihenfolge", "[]")
            try:
                spieler_reihenfolge = json.loads(spieler_reihenfolge_raw)
            except Exception:
                spieler_reihenfolge = []

            return {
                "players": players,
                "runde": runde,
                "abgerechnet": abgerechnet,
                "spieler_reihenfolge": spieler_reihenfolge,
            }

    @staticmethod
    def speichern_spiel(data: dict):
        """Schreibt das laufende Spiel in die Datenbank."""
        with DatenHandler._lock:
            conn = get_connection()
            try:
                # Spieler komplett ersetzen
                conn.execute("DELETE FROM aktuelles_spiel_spieler")
                players = data.get("players", {})
                for name, d in players.items():
                    punkte = d.get("punkte", [0, 0, 0, 0])
                    conn.execute(
                        """INSERT INTO aktuelles_spiel_spieler
                           (name, typ, punkte_r1, punkte_r2, punkte_r3, punkte_r4,
                            pumpen, neuner, kranz, position, offene_zahlung)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                        (
                            name,
                            d.get("typ", "Stamm"),
                            int(punkte[0]) if len(punkte) > 0 else 0,
                            int(punkte[1]) if len(punkte) > 1 else 0,
                            int(punkte[2]) if len(punkte) > 2 else 0,
                            int(punkte[3]) if len(punkte) > 3 else 0,
                            int(d.get("pumpen", 0)),
                            int(d.get("neuner", 0)),
                            int(d.get("kranz", 0)),
                            int(d.get("position", 0)),
                            float(d.get("offene_zahlung", 0.0)),
                        ),
                    )

                # Meta komplett ersetzen
                conn.execute("DELETE FROM aktuelles_spiel_meta")
                runde = data.get("runde", 0)
                abgerechnet = data.get("abgerechnet", False)
                spieler_reihenfolge = data.get("spieler_reihenfolge", list(players.keys()))
                conn.executemany(
                    "INSERT INTO aktuelles_spiel_meta (schluessel, wert) VALUES (?, ?)",
                    [
                        ("runde", str(runde)),
                        ("abgerechnet", str(abgerechnet).lower()),
                        ("spieler_reihenfolge", json.dumps(spieler_reihenfolge, ensure_ascii=False)),
                    ],
                )
                conn.commit()
            except Exception as e:
                conn.rollback()
                logging.error(f"Speichern aktuelles Spiel fehlgeschlagen: {e}")

    # ------------------------------------------------------------------
    # Offene Zahlungen
    # ------------------------------------------------------------------

    @staticmethod
    def reduziere_ausstehende_zahlung(player: str, betrag: float) -> bool:
        """Reduziert die offene Zahlung eines Spielers in der mitglieder-Tabelle."""
        with DatenHandler._lock:
            conn = get_connection()
            try:
                row = conn.execute(
                    "SELECT offene_zahlung FROM mitglieder WHERE name = ?", (player,)
                ).fetchone()
                if row is not None:
                    neue_schuld = max(0.0, float(row["offene_zahlung"]) - float(betrag))
                    conn.execute(
                        "UPDATE mitglieder SET offene_zahlung = ? WHERE name = ?",
                        (neue_schuld, player),
                    )
                    conn.commit()
                return True
            except Exception as e:
                conn.rollback()
                logging.error(f"Reduzieren offene Zahlung fehlgeschlagen ({player}): {e}")
                return False

    # ------------------------------------------------------------------
    # Archiv
    # ------------------------------------------------------------------

    @staticmethod
    def archivieren_spiel(spieldaten: dict):
        """Schreibt ein abgeschlossenes Spiel in die Historie-Tabellen."""
        with DatenHandler._lock:
            conn = get_connection()
            try:
                players = spieldaten.get("players", {})
                if "spieler_reihenfolge" not in spieldaten:
                    spieldaten["spieler_reihenfolge"] = list(players.keys())

                datum = spieldaten.get("datum", datetime.now().strftime("%d.%m.%Y"))
                spieler_reihenfolge_json = json.dumps(
                    spieldaten["spieler_reihenfolge"], ensure_ascii=False
                )

                cur = conn.execute(
                    "INSERT INTO historie (datum, spieler_reihenfolge) VALUES (?, ?)",
                    (datum, spieler_reihenfolge_json),
                )
                spiel_id = cur.lastrowid

                for name, d in players.items():
                    punkte = d.get("punkte", [0, 0, 0, 0])
                    conn.execute(
                        """INSERT INTO historie_spieler
                           (spiel_id, name, typ, punkte_r1, punkte_r2, punkte_r3, punkte_r4,
                            pumpen, neuner, kranz, offene_zahlung)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                        (
                            spiel_id,
                            name,
                            d.get("typ", "Stamm"),
                            int(punkte[0]) if len(punkte) > 0 else 0,
                            int(punkte[1]) if len(punkte) > 1 else 0,
                            int(punkte[2]) if len(punkte) > 2 else 0,
                            int(punkte[3]) if len(punkte) > 3 else 0,
                            int(d.get("pumpen", 0)),
                            int(d.get("neuner", 0)),
                            int(d.get("kranz", 0)),
                            float(d.get("offene_zahlung", 0.0)),
                        ),
                    )

                # Transaktionen des Spiels archivieren
                for tx in spieldaten.get("transaktionen", []):
                    conn.execute(
                        "INSERT INTO historie_transaktionen (spiel_id, text) VALUES (?, ?)",
                        (spiel_id, tx),
                    )

                conn.commit()
            except Exception as e:
                conn.rollback()
                logging.error(f"Speichern Historie fehlgeschlagen: {e}")

    @staticmethod
    def laden_letzte_reihenfolge() -> list:
        """Gibt die Spielerreihenfolge des letzten archivierten Spiels zurück."""
        with DatenHandler._lock:
            conn = get_connection()
            row = conn.execute(
                "SELECT spieler_reihenfolge FROM historie ORDER BY id DESC LIMIT 1"
            ).fetchone()
            if row and row["spieler_reihenfolge"]:
                try:
                    return json.loads(row["spieler_reihenfolge"])
                except Exception:
                    pass
            return []

    @staticmethod
    def laden_historie() -> list:
        """Gibt alle Historieeinträge zurück (für Archiv-Ansicht)."""
        with DatenHandler._lock:
            conn = get_connection()
            spiele = conn.execute(
                "SELECT id, datum, spieler_reihenfolge FROM historie ORDER BY id DESC LIMIT 100"
            ).fetchall()
            result = []
            for spiel in spiele:
                spieler_rows = conn.execute(
                    "SELECT * FROM historie_spieler WHERE spiel_id = ?", (spiel["id"],)
                ).fetchall()
                tx_rows = conn.execute(
                    "SELECT text FROM historie_transaktionen WHERE spiel_id = ? ORDER BY id",
                    (spiel["id"],)
                ).fetchall()

                players = {}
                for sr in spieler_rows:
                    players[sr["name"]] = {
                        "typ": sr["typ"],
                        "punkte": [sr["punkte_r1"], sr["punkte_r2"], sr["punkte_r3"], sr["punkte_r4"]],
                        "pumpen": sr["pumpen"],
                        "neuner": sr["neuner"],
                        "kranz": sr["kranz"],
                        "offene_zahlung": sr["offene_zahlung"],
                    }

                try:
                    reihenfolge = json.loads(spiel["spieler_reihenfolge"] or "[]")
                except Exception:
                    reihenfolge = list(players.keys())

                result.append({
                    "datum": spiel["datum"],
                    "players": players,
                    "transaktionen": [r["text"] for r in tx_rows],
                    "spieler_reihenfolge": reihenfolge,
                })
            return result
