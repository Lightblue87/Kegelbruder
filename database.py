"""
database.py – SQLite-Verbindung und Schema-Initialisierung

Singleton-Verbindung mit WAL-Modus für bessere Nebenläufigkeit
(z. B. bei OneDrive-Synchronisation).
"""

import sqlite3
import logging

from config import get_db_path

_connection: sqlite3.Connection | None = None


def get_connection() -> sqlite3.Connection:
    """Gibt die gecachte SQLite-Verbindung zurück (erstellt sie beim ersten Aufruf)."""
    global _connection
    if _connection is None:
        db_path = get_db_path()
        _connection = sqlite3.connect(db_path, check_same_thread=False)
        _connection.row_factory = sqlite3.Row
        _connection.execute("PRAGMA journal_mode=WAL")
        _connection.execute("PRAGMA foreign_keys=ON")
        logging.info(f"SQLite-Verbindung geöffnet: {db_path}")
    return _connection


def init_db():
    """Erstellt alle Tabellen falls nicht vorhanden und fügt Standard-Kassenwerte ein."""
    conn = get_connection()
    cur = conn.cursor()

    cur.executescript("""
        CREATE TABLE IF NOT EXISTS mitglieder (
            name TEXT PRIMARY KEY,
            typ TEXT NOT NULL DEFAULT 'Stamm',
            offene_zahlung REAL NOT NULL DEFAULT 0.0
        );

        CREATE TABLE IF NOT EXISTS kasse_einstellungen (
            schluessel TEXT PRIMARY KEY,
            wert REAL NOT NULL DEFAULT 0.0
        );

        CREATE TABLE IF NOT EXISTS transaktionen (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS aktuelles_spiel_spieler (
            name TEXT PRIMARY KEY,
            typ TEXT NOT NULL DEFAULT 'Stamm',
            punkte_r1 INTEGER NOT NULL DEFAULT 0,
            punkte_r2 INTEGER NOT NULL DEFAULT 0,
            punkte_r3 INTEGER NOT NULL DEFAULT 0,
            punkte_r4 INTEGER NOT NULL DEFAULT 0,
            pumpen INTEGER NOT NULL DEFAULT 0,
            neuner INTEGER NOT NULL DEFAULT 0,
            kranz INTEGER NOT NULL DEFAULT 0,
            position INTEGER NOT NULL DEFAULT 0,
            offene_zahlung REAL NOT NULL DEFAULT 0.0
        );

        CREATE TABLE IF NOT EXISTS aktuelles_spiel_meta (
            schluessel TEXT PRIMARY KEY,
            wert TEXT NOT NULL DEFAULT ''
        );

        CREATE TABLE IF NOT EXISTS historie (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            datum TEXT NOT NULL,
            spieler_reihenfolge TEXT
        );

        CREATE TABLE IF NOT EXISTS historie_spieler (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            spiel_id INTEGER NOT NULL REFERENCES historie(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            typ TEXT,
            punkte_r1 INTEGER DEFAULT 0,
            punkte_r2 INTEGER DEFAULT 0,
            punkte_r3 INTEGER DEFAULT 0,
            punkte_r4 INTEGER DEFAULT 0,
            pumpen INTEGER DEFAULT 0,
            neuner INTEGER DEFAULT 0,
            kranz INTEGER DEFAULT 0,
            offene_zahlung REAL DEFAULT 0.0
        );

        CREATE TABLE IF NOT EXISTS historie_transaktionen (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            spiel_id INTEGER NOT NULL REFERENCES historie(id) ON DELETE CASCADE,
            text TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS app_lock (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            geraet TEXT NOT NULL,
            seit TEXT NOT NULL,
            plattform TEXT NOT NULL
        );
    """)

    # Standard-Kassenwerte einfügen (nur wenn noch nicht vorhanden)
    defaults = [
        ("Startgeld", 5.0),
        ("Pumpe", 0.5),
        ("Neuner", 1.0),
        ("Kranz", 2.0),
        ("Strafe Stamm", 7.5),
        ("Bahngebühr", 30.0),
        ("Kassenstand", 0.0),
        ("Letzte_Startgebuehren", 0.0),
    ]
    cur.executemany(
        "INSERT OR IGNORE INTO kasse_einstellungen (schluessel, wert) VALUES (?, ?)",
        defaults
    )

    conn.commit()
    logging.info("Datenbank initialisiert.")
