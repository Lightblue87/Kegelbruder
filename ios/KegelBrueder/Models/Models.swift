import Foundation

// MARK: - Raw JSON Codable types (match Python app's JSON format exactly)

struct MitgliederFile: Codable {
    var players: [String: PlayerData]
}

struct PlayerData: Codable {
    var typ: String
    var punkte: [Int]
    var offene_zahlung: Double
    var pumpen: Int?
    var neuner: Int?
    var kranz: Int?
    var position: Int?

    init(typ: String = "Stamm") {
        self.typ = typ
        self.punkte = [0, 0, 0, 0]
        self.offene_zahlung = 0.0
        self.pumpen = 0
        self.neuner = 0
        self.kranz = 0
    }
}

struct AktuellesSpielFile: Codable {
    var players: [String: PlayerData]
    var runde: Int
    var abgerechnet: Bool
    var spieler_reihenfolge: [String]?
}

struct KasseFile: Codable {
    var Startgeld: Double
    var Pumpe: Double
    var Neuner: Double
    var Kranz: Double
    var Strafe_Stamm: Double
    var Bahngebuehr: Double
    var Kassenstand: Double
    var Kontostand: Double
    var Transaktionen: [String]
    var Letzte_Startgebuehren: Double

    enum CodingKeys: String, CodingKey {
        case Startgeld, Pumpe, Neuner, Kranz
        case Strafe_Stamm = "Strafe Stamm"
        case Bahngebuehr = "Bahngebühr"
        case Kassenstand, Kontostand, Transaktionen
        case Letzte_Startgebuehren = "Letzte_Startgebuehren"
    }

    static var defaultValue: KasseFile {
        KasseFile(
            Startgeld: 5.0, Pumpe: 0.5, Neuner: 1.0, Kranz: 2.0,
            Strafe_Stamm: 7.5, Bahngebuehr: 30.0,
            Kassenstand: 0.0, Kontostand: 0.0, Transaktionen: [], Letzte_Startgebuehren: 0.0
        )
    }
}

struct HistorieEntry: Codable, Identifiable, Hashable {
    var id: String { "\(spielId)" }
    var spielId: Int
    var datum: String
    var players: [String: PlayerData]
    var transaktionen: [String]
    var spieler_reihenfolge: [String]?

    func hash(into hasher: inout Hasher) { hasher.combine(spielId) }
    static func == (lhs: HistorieEntry, rhs: HistorieEntry) -> Bool { lhs.spielId == rhs.spielId }
}

struct AppLockFile: Codable {
    var gerät: String
    var seit: String
    var plattform: String
}

// MARK: - App-friendly Player model (used in ViewModels/Views)

struct Player: Identifiable {
    var id: String { name }
    var name: String
    var typ: String
    var punkte: [Int]
    var offene_zahlung: Double
    var pumpen: Int
    var neuner: Int
    var kranz: Int
    var position: Int?

    init(name: String, data: PlayerData) {
        self.name = name
        self.typ = data.typ
        self.punkte = data.punkte.count == 4 ? data.punkte : [0, 0, 0, 0]
        self.offene_zahlung = data.offene_zahlung
        self.pumpen = data.pumpen ?? 0
        self.neuner = data.neuner ?? 0
        self.kranz = data.kranz ?? 0
        self.position = data.position
    }

    init(name: String, typ: String = "Stamm") {
        self.name = name
        self.typ = typ
        self.punkte = [0, 0, 0, 0]
        self.offene_zahlung = 0.0
        self.pumpen = 0
        self.neuner = 0
        self.kranz = 0
    }

    var summe: Int { punkte.reduce(0, +) }
    var istStamm: Bool { typ == "Stamm" }

    func toPlayerData() -> PlayerData {
        PlayerData(
            typ: typ, punkte: punkte, offene_zahlung: offene_zahlung,
            pumpen: pumpen, neuner: neuner, kranz: kranz, position: position
        )
    }
}

extension PlayerData {
    init(typ: String, punkte: [Int], offene_zahlung: Double,
         pumpen: Int?, neuner: Int?, kranz: Int?, position: Int?) {
        self.typ = typ
        self.punkte = punkte
        self.offene_zahlung = offene_zahlung
        self.pumpen = pumpen
        self.neuner = neuner
        self.kranz = kranz
        self.position = position
    }
}

// MARK: - Billing result

struct BillingRow: Identifiable {
    var id: String { player.name }
    var platz: Int
    var player: Player
    var zuZahlen: Double
    var gezahlt: Double = 0.0
    var spende: Double { max(0, gezahlt - zuZahlen) }
}

// MARK: - Tiebreak state

struct TiebreakExtra {
    var pumpen: Int = 0
    var neuner: Int = 0
    var kranz: Int = 0
    var punkte: Int = 0
}
