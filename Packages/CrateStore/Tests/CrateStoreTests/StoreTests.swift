import Foundation
import GRDB
import Testing
import CrateKit
import CrateStore
import CrateStoreTestSupport

@Test func emptyDatabaseMigratesToFrozenV1() throws {
    let store = try CrateStore.inMemory()
    let tables = try store.db.read { db in
        try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('games','people','plays','play_players')"))
    }
    #expect(tables == ["games", "people", "plays", "play_players"])
    #expect(try store.db.read { db in try CrateStoreSchema.migrator.appliedMigrations(db) } == ["v1"])
}

@Test func gameAndPersonRoundTripPreservesUnknownsAndCategories() throws {
    let store = try CrateStore.inMemory()
    let game = Game(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "  Azul  ", categories: ["abstract", "family"], createdAt: Date(timeIntervalSince1970: 123), notes: "shelf")
    let person = Person(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "  Ana  ", notes: "friend")
    try GRDBGameRepository(db: store.db).save(game)
    try GRDBPersonRepository(db: store.db).save(person)
    #expect(try GRDBGameRepository(db: store.db).game(id: game.id) == game)
    #expect(try GRDBPersonRepository(db: store.db).person(id: person.id) == person)
}

@Test func playLedgerAppendsRatingsAndCorrectionsWithoutRewriting() throws {
    let store = try CrateStore.inMemory()
    let game = Game(title: "Azul")
    let person = Person(name: "Ana")
    try GRDBGameRepository(db: store.db).save(game)
    try GRDBPersonRepository(db: store.db).save(person)
    let ledger = GRDBPlayLedgerRepository(db: store.db)
    let first = PlayEvent(gameID: game.id, occurredAt: Date(timeIntervalSince1970: 100), participants: [PlayParticipant(personID: person.id, rating: Rating(rawValue: 4), notes: "good")], notes: "first")
    try ledger.append(first)
    let correction = PlayEvent(gameID: game.id, occurredAt: Date(timeIntervalSince1970: 101), participants: [PlayParticipant(personID: person.id, rating: Rating(rawValue: 5))], correctionOf: first.id)
    try ledger.append(correction)
    #expect(try ledger.events(for: game.id) == [first, correction])
    #expect(throws: PlayLedgerError.duplicateEventID(first.id)) { try ledger.append(first) }
    let rows = try store.db.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays") }
    #expect(rows == 2)
}

@Test func inMemoryFakesShareRepositoryContracts() throws {
    let games: any GameRepository = InMemoryGameRepository()
    let people: any PersonRepository = InMemoryPersonRepository()
    let ledger: any PlayLedgerRepository = InMemoryPlayLedgerRepository()
    let game = Game(title: "Azul")
    let person = Person(name: "Ana")
    try games.save(game)
    try people.save(person)
    let event = PlayEvent(gameID: game.id, participants: [PlayParticipant(personID: person.id, rating: Rating(rawValue: 5))])
    try ledger.append(event)
    #expect(try games.allGames() == [game])
    #expect(try people.allPeople() == [person])
    #expect(try ledger.events(for: game.id) == [event])
    #expect(throws: PlayLedgerError.duplicateEventID(event.id)) { try ledger.append(event) }
}

@Test func committedV1FixtureMigratesAndReadsDomainRows() throws {
    let source = try #require(Bundle.module.url(forResource: "v1", withExtension: "sqlite"))
    let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    defer { try? FileManager.default.removeItem(at: target) }
    try FileManager.default.copyItem(at: source, to: target)
    let store = try CrateStore.atPath(target.path)
    #expect(try store.db.read { db in try CrateStoreSchema.migrator.appliedMigrations(db) } == ["v1"])
    #expect(try GRDBGameRepository(db: store.db).allGames().map(\.title) == ["Azul"])
    #expect(try GRDBPersonRepository(db: store.db).allPeople().map(\.name) == ["Ana"])
    #expect(try GRDBPlayLedgerRepository(db: store.db).events(for: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!).count == 1)
}

@Test func playRowsRejectInPlaceUpdatesAndDirectDeletes() throws {
    let store = try CrateStore.inMemory()
    let game = Game(title: "Azul")
    let person = Person(name: "Ana")
    try GRDBGameRepository(db: store.db).save(game)
    try GRDBPersonRepository(db: store.db).save(person)
    let event = PlayEvent(gameID: game.id, participants: [PlayParticipant(personID: person.id, rating: Rating(rawValue: 4))])
    try GRDBPlayLedgerRepository(db: store.db).append(event)
    #expect(throws: (any Error).self) {
        try store.db.write { db in try db.execute(sql: "UPDATE plays SET notes='changed' WHERE id=?", arguments: [event.id.uuidString]) }
    }
    #expect(throws: (any Error).self) {
        try store.db.write { db in try db.execute(sql: "UPDATE play_players SET rating=5 WHERE play_id=?", arguments: [event.id.uuidString]) }
    }
    #expect(throws: (any Error).self) {
        try store.db.write { db in try db.execute(sql: "DELETE FROM play_players WHERE play_id=?", arguments: [event.id.uuidString]) }
    }
    #expect(throws: (any Error).self) {
        try store.db.write { db in try db.execute(sql: "DELETE FROM plays WHERE id=?", arguments: [event.id.uuidString]) }
    }
    #expect(try GRDBPlayLedgerRepository(db: store.db).events(for: game.id) == [event])
}

@Test func v1ForeignKeysIndexesAndCascadeAreEnforced() throws {
    let store = try CrateStore.inMemory()
    try store.db.read { db in
        for (table, column, parent) in [("plays", "game_id", "games"), ("play_players", "play_id", "plays"), ("play_players", "person_id", "people")] {
            let rows = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list(\(table))")
            #expect(rows.contains { row in
                let from: String = row["from"]
                let to: String = row["table"]
                let action: String = row["on_delete"]
                return from == column && to == parent && action == "CASCADE"
            })
        }
        let indexes = try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index'"))
        #expect(indexes.isSuperset(of: ["plays_occurred_at", "plays_game_id", "play_players_person_id"]))
    }
    let game = Game(title: "Azul")
    let person = Person(name: "Ana")
    try GRDBGameRepository(db: store.db).save(game)
    try GRDBPersonRepository(db: store.db).save(person)
    try GRDBPlayLedgerRepository(db: store.db).append(PlayEvent(gameID: game.id, participants: [PlayParticipant(personID: person.id)]))
    try GRDBGameRepository(db: store.db).deleteGame(id: game.id)
    #expect(try store.db.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays") } == 0)
    #expect(try store.db.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM play_players") } == 0)
}

@Test func orphanParticipantsAreRejectedAndDeletingPersonKeepsPlay() throws {
    let store = try CrateStore.inMemory()
    let game = Game(title: "Azul")
    let person = Person(name: "Ana")
    try GRDBGameRepository(db: store.db).save(game)
    let event = PlayEvent(gameID: game.id, participants: [PlayParticipant(personID: person.id)])
    #expect(throws: (any Error).self) { try GRDBPlayLedgerRepository(db: store.db).append(event) }
    #expect(try store.db.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays") } == 0)
    try GRDBPersonRepository(db: store.db).save(person)
    try GRDBPlayLedgerRepository(db: store.db).append(event)
    try GRDBPersonRepository(db: store.db).deletePerson(id: person.id)
    #expect(try store.db.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays") } == 1)
    #expect(try store.db.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM play_players") } == 0)
}
