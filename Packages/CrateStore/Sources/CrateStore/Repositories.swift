import Foundation
import GRDB
import CrateKit

public protocol GameRepository: Sendable {
    func save(_ game: Game) throws
    func game(id: UUID) throws -> Game?
    func allGames() throws -> [Game]
    func deleteGame(id: UUID) throws
}

public protocol PersonRepository: Sendable {
    func save(_ person: Person) throws
    func person(id: UUID) throws -> Person?
    func allPeople() throws -> [Person]
    func deletePerson(id: UUID) throws
}

public protocol PlayLedgerRepository: Sendable {
    /// Inserts an immutable event and its participants atomically. Corrections are additional events.
    func append(_ event: PlayEvent) throws
    func events(for gameID: UUID) throws -> [PlayEvent]
}

private func timestamp(_ date: Date?) -> Double? { date?.timeIntervalSince1970 }
private func date(_ value: Double?) -> Date? { value.map(Date.init(timeIntervalSince1970:)) }
private func uuid(_ text: String) throws -> UUID {
    guard let value = UUID(uuidString: text) else { throw CrateStoreError.corruptUUID(text) }
    return value
}

/// Reported when a stored row cannot be decoded back into its CrateKit domain
/// type. Corruption is diagnosable instead of silently defaulted.
public enum CrateStoreError: Error, Equatable, Sendable {
    case corruptUUID(String)
    case corruptRating(Int)
}

public struct GRDBGameRepository: GameRepository {
    private let db: any DatabaseWriter
    public init(db: any DatabaseWriter) { self.db = db }

    public func save(_ game: Game) throws {
        let categories = String(decoding: try JSONEncoder().encode(game.categories), as: UTF8.self)
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO games (id,title,minimum_players,maximum_players,play_time_minutes,categories_json,created_at,notes)
                VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
                  title=excluded.title, minimum_players=excluded.minimum_players,
                  maximum_players=excluded.maximum_players, play_time_minutes=excluded.play_time_minutes,
                  categories_json=excluded.categories_json, created_at=excluded.created_at, notes=excluded.notes
                """, arguments: [game.id.uuidString, game.title, game.minimumPlayers, game.maximumPlayers,
                                 game.playTimeMinutes, categories, timestamp(game.createdAt), game.notes])
        }
    }

    public func game(id: UUID) throws -> Game? {
        try db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM games WHERE id=?", arguments: [id.uuidString]) else { return nil }
            return try Self.decode(row)
        }
    }

    public func allGames() throws -> [Game] {
        try db.read { db in try Row.fetchAll(db, sql: "SELECT * FROM games ORDER BY title COLLATE NOCASE, id").map(Self.decode) }
    }

    public func deleteGame(id: UUID) throws {
        try db.write { db in try db.execute(sql: "DELETE FROM games WHERE id=?", arguments: [id.uuidString]) }
    }

    private static func decode(_ row: Row) throws -> Game {
        let categories: String = row["categories_json"]
        return try Game(id: try uuid(row["id"]), title: row["title"], minimumPlayers: row["minimum_players"],
                        maximumPlayers: row["maximum_players"], playTimeMinutes: row["play_time_minutes"],
                        categories: JSONDecoder().decode([CategoryTag].self, from: Data(categories.utf8)),
                        createdAt: date(row["created_at"]), notes: row["notes"])
    }
}

public struct GRDBPersonRepository: PersonRepository {
    private let db: any DatabaseWriter
    public init(db: any DatabaseWriter) { self.db = db }

    public func save(_ person: Person) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO people (id,name,created_at,notes) VALUES (?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name, created_at=excluded.created_at, notes=excluded.notes
                """, arguments: [person.id.uuidString, person.name, timestamp(person.createdAt), person.notes])
        }
    }

    public func person(id: UUID) throws -> Person? {
        try db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM people WHERE id=?", arguments: [id.uuidString]) else { return nil }
            return try Self.decode(row)
        }
    }

    public func allPeople() throws -> [Person] {
        try db.read { db in try Row.fetchAll(db, sql: "SELECT * FROM people ORDER BY name COLLATE NOCASE, id").map(Self.decode) }
    }

    public func deletePerson(id: UUID) throws {
        try db.write { db in try db.execute(sql: "DELETE FROM people WHERE id=?", arguments: [id.uuidString]) }
    }

    private static func decode(_ row: Row) throws -> Person {
        Person(id: try uuid(row["id"]), name: row["name"], createdAt: date(row["created_at"]), notes: row["notes"])
    }
}

public struct GRDBPlayLedgerRepository: PlayLedgerRepository {
    private let db: any DatabaseWriter
    public init(db: any DatabaseWriter) { self.db = db }

    public func append(_ event: PlayEvent) throws {
        try db.write { db in
            if try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays WHERE id=?", arguments: [event.id.uuidString]) == 1 {
                throw PlayLedgerError.duplicateEventID(event.id)
            }
            if let targetID = event.correctionOf {
                guard let row = try Row.fetchOne(db, sql: "SELECT game_id FROM plays WHERE id=?", arguments: [targetID.uuidString]) else {
                    throw PlayLedgerError.correctedEventNotFound(targetID)
                }
                let targetGameID = try uuid(row["game_id"])
                guard targetGameID == event.gameID else {
                    throw PlayLedgerError.gameMismatch(expected: targetGameID, actual: event.gameID)
                }
                var history = PlayLedger(events: try Self.readEvents(db, gameID: event.gameID))
                try history.append(event)
            }
            try db.execute(sql: "INSERT INTO plays (id,game_id,occurred_at,notes,correction_of) VALUES (?,?,?,?,?)",
                           arguments: [event.id.uuidString, event.gameID.uuidString, timestamp(event.occurredAt), event.notes, event.correctionOf?.uuidString])
            for participant in event.participants {
                try db.execute(sql: "INSERT INTO play_players (play_id,person_id,rating,notes) VALUES (?,?,?,?)",
                               arguments: [event.id.uuidString, participant.personID.uuidString, participant.rating?.rawValue, participant.notes])
            }
        }
    }

    public func events(for gameID: UUID) throws -> [PlayEvent] {
        try db.read { db in try Self.readEvents(db, gameID: gameID) }
    }

    private static func readEvents(_ db: Database, gameID: UUID) throws -> [PlayEvent] {
        try Row.fetchAll(db, sql: "SELECT * FROM plays WHERE game_id=? ORDER BY rowid", arguments: [gameID.uuidString]).map { row in
            let id = try uuid(row["id"])
            let participants = try Row.fetchAll(db, sql: "SELECT * FROM play_players WHERE play_id=? ORDER BY rowid", arguments: [id.uuidString]).map { player in
                let ratingValue: Int? = player["rating"]
                let rating: Rating?
                if let raw = ratingValue {
                    guard let r = Rating(rawValue: raw) else { throw CrateStoreError.corruptRating(raw) }
                    rating = r
                } else {
                    rating = nil
                }
                return PlayParticipant(personID: try uuid(player["person_id"]), rating: rating, notes: player["notes"])
            }
            let correction: String? = row["correction_of"]
            return PlayEvent(id: id, gameID: gameID, occurredAt: date(row["occurred_at"]), participants: participants,
                             notes: row["notes"], correctionOf: try correction.map(uuid))
        }
    }
}
