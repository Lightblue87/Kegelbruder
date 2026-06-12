import Foundation
import SQLite3

// MARK: - SQLiteStore: thin wrapper around SQLite3 C API
// Uses the same schema as the desktop Python app (kegelbruder.db)

final class SQLiteStore {

    private var db: OpaquePointer?
    private(set) var path: String

    init(path: String) throws {
        self.path = path
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw SQLiteError.openFailed(path)
        }
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA foreign_keys=ON")
        try createSchema()
        try insertDefaultKasse()
    }

    deinit { sqlite3_close(db) }

    // MARK: - Schema

    private func createSchema() throws {
        // sqlite3_prepare_v2 only compiles the first statement in a multi-statement string.
        // Use sqlite3_exec which processes all statements in one call.
        let sql = """
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
        """
        var errmsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errmsg) == SQLITE_OK else {
            let msg = errmsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errmsg)
            throw SQLiteError.stepFailed(msg)
        }
    }

    private func insertDefaultKasse() throws {
        let defaults: [(String, Double)] = [
            ("Startgeld", 5.0), ("Pumpe", 0.5), ("Neuner", 1.0), ("Kranz", 2.0),
            ("Strafe Stamm", 7.5), ("Bahngebühr", 30.0),
            ("Kassenstand", 0.0), ("Kontostand", 0.0), ("Letzte_Startgebuehren", 0.0)
        ]
        for (key, val) in defaults {
            try exec("INSERT OR IGNORE INTO kasse_einstellungen (schluessel, wert) VALUES (?, ?)",
                     params: [.text(key), .real(val)])
        }
    }

    // MARK: - Mitglieder

    func ladeMitglieder() -> [String: PlayerData] {
        var result: [String: PlayerData] = [:]
        try? query("SELECT name, typ, offene_zahlung FROM mitglieder") { row in
            let name = row.text(0)
            result[name] = PlayerData(
                typ: row.text(1),
                punkte: [0, 0, 0, 0],
                offene_zahlung: row.real(2),
                pumpen: 0, neuner: 0, kranz: 0, position: nil
            )
        }
        return result
    }

    func speichereMitglieder(_ players: [String: PlayerData]) throws {
        try transaction {
            try exec("DELETE FROM mitglieder")
            for (name, d) in players {
                try exec(
                    "INSERT INTO mitglieder (name, typ, offene_zahlung) VALUES (?, ?, ?)",
                    params: [.text(name), .text(d.typ), .real(d.offene_zahlung)]
                )
            }
        }
    }

    func reduziereOffeneZahlung(name: String, betrag: Double) throws {
        try transaction {
            var current = 0.0
            try query("SELECT offene_zahlung FROM mitglieder WHERE name = ?",
                      params: [.text(name)]) { row in current = row.real(0) }
            let neu = max(0.0, current - betrag)
            try exec("UPDATE mitglieder SET offene_zahlung = ? WHERE name = ?",
                     params: [.real(neu), .text(name)])
        }
    }

    // MARK: - Kasse

    func ladeKasseEinstellungen() -> [String: Double] {
        var result: [String: Double] = [:]
        try? query("SELECT schluessel, wert FROM kasse_einstellungen") { row in
            result[row.text(0)] = row.real(1)
        }
        return result
    }

    func ladeTransaktionen(limit: Int = 200) -> [String] {
        var result: [String] = []
        try? query(
            "SELECT text FROM transaktionen ORDER BY id DESC LIMIT ?",
            params: [.int(limit)]
        ) { row in result.append(row.text(0)) }
        return result.reversed()
    }

    func speichereKasse(einstellungen: [String: Double], transaktionen: [String]) throws {
        try transaction {
            for (key, val) in einstellungen {
                try exec(
                    "INSERT OR REPLACE INTO kasse_einstellungen (schluessel, wert) VALUES (?, ?)",
                    params: [.text(key), .real(val)]
                )
            }
            try exec("DELETE FROM transaktionen")
            for tx in transaktionen {
                try exec("INSERT INTO transaktionen (text) VALUES (?)", params: [.text(tx)])
            }
        }
    }

    // MARK: - Aktuelles Spiel

    func ladeAktuellesSpiel() -> AktuellesSpielFile {
        var players: [String: PlayerData] = [:]
        try? query("""
            SELECT name, typ, punkte_r1, punkte_r2, punkte_r3, punkte_r4,
                   pumpen, neuner, kranz, position, offene_zahlung
            FROM aktuelles_spiel_spieler ORDER BY position
            """) { row in
            let name = row.text(0)
            players[name] = PlayerData(
                typ: row.text(1),
                punkte: [row.int(2), row.int(3), row.int(4), row.int(5)],
                offene_zahlung: row.real(10),
                pumpen: row.int(6), neuner: row.int(7), kranz: row.int(8),
                position: row.int(9)
            )
        }

        var meta: [String: String] = [:]
        try? query("SELECT schluessel, wert FROM aktuelles_spiel_meta") { row in
            meta[row.text(0)] = row.text(1)
        }

        let runde = Int(meta["runde"] ?? "0") ?? 0
        let abgerechnet = (meta["abgerechnet"] ?? "false") == "true"
        let reihenfolge = (try? JSONDecoder().decode(
            [String].self,
            from: Data((meta["spieler_reihenfolge"] ?? "[]").utf8)
        )) ?? []

        return AktuellesSpielFile(
            players: players, runde: runde,
            abgerechnet: abgerechnet, spieler_reihenfolge: reihenfolge
        )
    }

    func speichereAktuellesSpiel(_ spiel: AktuellesSpielFile) throws {
        try transaction {
            try exec("DELETE FROM aktuelles_spiel_spieler")
            for (idx, name) in (spiel.spieler_reihenfolge ?? Array(spiel.players.keys)).enumerated() {
                guard let d = spiel.players[name] else { continue }
                let p = d.punkte.count == 4 ? d.punkte : [0, 0, 0, 0]
                try exec("""
                    INSERT INTO aktuelles_spiel_spieler
                    (name,typ,punkte_r1,punkte_r2,punkte_r3,punkte_r4,
                     pumpen,neuner,kranz,position,offene_zahlung)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?)
                    """, params: [
                        .text(name), .text(d.typ),
                        .int(p[0]), .int(p[1]), .int(p[2]), .int(p[3]),
                        .int(d.pumpen ?? 0), .int(d.neuner ?? 0), .int(d.kranz ?? 0),
                        .int(idx), .real(d.offene_zahlung)
                    ])
            }

            try exec("DELETE FROM aktuelles_spiel_meta")
            let reihenfolgeJSON = (try? String(
                data: JSONEncoder().encode(spiel.spieler_reihenfolge ?? []),
                encoding: .utf8
            )) ?? "[]"
            let meta: [(String, String)] = [
                ("runde", "\(spiel.runde)"),
                ("abgerechnet", spiel.abgerechnet ? "true" : "false"),
                ("spieler_reihenfolge", reihenfolgeJSON)
            ]
            for (k, v) in meta {
                try exec("INSERT INTO aktuelles_spiel_meta (schluessel, wert) VALUES (?, ?)",
                         params: [.text(k), .text(v)])
            }
        }
    }

    // MARK: - Historie

    func ladeHistorie(limit: Int = 100) -> [HistorieEntry] {
        var entries: [HistorieEntry] = []
        try? query(
            "SELECT id, datum, spieler_reihenfolge FROM historie ORDER BY id DESC LIMIT ?",
            params: [.int(limit)]
        ) { spiel in
            let spielId = spiel.int(0)
            let datum   = spiel.text(1)
            let reihenfolge = (try? JSONDecoder().decode(
                [String].self,
                from: Data((spiel.text(2)).utf8)
            )) ?? []

            var players: [String: PlayerData] = [:]
            try? query(
                """
                SELECT name, typ, punkte_r1, punkte_r2, punkte_r3, punkte_r4,
                       pumpen, neuner, kranz, offene_zahlung
                FROM historie_spieler WHERE spiel_id = ?
                """,
                params: [.int(spielId)]
            ) { row in
                players[row.text(0)] = PlayerData(
                    typ: row.text(1),
                    punkte: [row.int(2), row.int(3), row.int(4), row.int(5)],
                    offene_zahlung: row.real(9),
                    pumpen: row.int(6), neuner: row.int(7), kranz: row.int(8),
                    position: nil
                )
            }

            var transaktionen: [String] = []
            try? query(
                "SELECT text FROM historie_transaktionen WHERE spiel_id = ? ORDER BY id",
                params: [.int(spielId)]
            ) { row in transaktionen.append(row.text(0)) }

            entries.append(HistorieEntry(
                spielId: spielId, datum: datum, players: players,
                transaktionen: transaktionen, spieler_reihenfolge: reihenfolge
            ))
        }
        return entries
    }

    func archivierSpiel(datum: String, players: [String: PlayerData],
                        transaktionen: [String], reihenfolge: [String]) throws {
        try transaction {
            let reihenfolgeJSON = (try? String(
                data: JSONEncoder().encode(reihenfolge), encoding: .utf8
            )) ?? "[]"
            try exec(
                "INSERT INTO historie (datum, spieler_reihenfolge) VALUES (?, ?)",
                params: [.text(datum), .text(reihenfolgeJSON)]
            )
            let spielId = Int(sqlite3_last_insert_rowid(db))
            for name in reihenfolge {
                guard let d = players[name] else { continue }
                let p = d.punkte.count == 4 ? d.punkte : [0, 0, 0, 0]
                try exec("""
                    INSERT INTO historie_spieler
                    (spiel_id,name,typ,punkte_r1,punkte_r2,punkte_r3,punkte_r4,
                     pumpen,neuner,kranz,offene_zahlung)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?)
                    """, params: [
                        .int(spielId), .text(name), .text(d.typ),
                        .int(p[0]), .int(p[1]), .int(p[2]), .int(p[3]),
                        .int(d.pumpen ?? 0), .int(d.neuner ?? 0), .int(d.kranz ?? 0),
                        .real(d.offene_zahlung)
                    ])
            }
            for tx in transaktionen {
                try exec(
                    "INSERT INTO historie_transaktionen (spiel_id, text) VALUES (?, ?)",
                    params: [.int(spielId), .text(tx)]
                )
            }
        }
    }

    // MARK: - Lock

    func ladeLock() -> AppLockFile? {
        var result: AppLockFile? = nil
        try? query("SELECT geraet, seit, plattform FROM app_lock WHERE id = 1") { row in
            result = AppLockFile(gerät: row.text(0), seit: row.text(1), plattform: row.text(2))
        }
        return result
    }

    func setzeLock(geraet: String, seit: String, plattform: String) throws {
        try exec(
            "INSERT OR REPLACE INTO app_lock (id, geraet, seit, plattform) VALUES (1, ?, ?, ?)",
            params: [.text(geraet), .text(seit), .text(plattform)]
        )
    }

    func loescheLock() throws {
        try exec("DELETE FROM app_lock WHERE id = 1")
    }

    // MARK: - Low-level helpers

    enum Param {
        case text(String?)
        case real(Double)
        case int(Int)
        case null
    }

    func exec(_ sql: String, params: [Param] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(sql, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func query(_ sql: String, params: [Param] = [], handler: (Row) throws -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(sql, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        while sqlite3_step(stmt) == SQLITE_ROW {
            try handler(Row(stmt: stmt!))
        }
    }

    func transaction(_ block: () throws -> Void) throws {
        try exec("BEGIN")
        do {
            try block()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func bind(_ stmt: OpaquePointer?, _ params: [Param]) {
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case .text(let s):
                if let s { sqlite3_bind_text(stmt, idx, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                else      { sqlite3_bind_null(stmt, idx) }
            case .real(let v): sqlite3_bind_double(stmt, idx, v)
            case .int(let v):  sqlite3_bind_int64(stmt, idx, Int64(v))
            case .null:        sqlite3_bind_null(stmt, idx)
            }
        }
    }

    // MARK: - Row accessor

    struct Row {
        let stmt: OpaquePointer
        func text(_ col: Int32) -> String {
            guard let p = sqlite3_column_text(stmt, col) else { return "" }
            return String(cString: p)
        }
        func real(_ col: Int32) -> Double { sqlite3_column_double(stmt, col) }
        func int(_ col: Int32)  -> Int    { Int(sqlite3_column_int64(stmt, col)) }
    }
}

enum SQLiteError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String, String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let p):      return "Datenbank konnte nicht geöffnet werden: \(p)"
        case .prepareFailed(let s, let e): return "SQL-Fehler [\(e)]: \(s)"
        case .stepFailed(let e):      return "Ausführungsfehler: \(e)"
        }
    }
}
