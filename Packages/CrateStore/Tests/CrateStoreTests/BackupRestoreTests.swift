import Foundation
import Testing
import CrateKit
import CrateStore

/// Restore keeps the frozen v1 schema untouched — these tests exercise the
/// snapshot/replace surface added for issue #7.
@Test("snapshot captures games, people, and the COMPLETE ledger including superseded originals")
func snapshotCapturesFullHistory() throws {
    let store = try CrateStore.inMemory()
    let games = GRDBGameRepository(db: store.db)
    let people = GRDBPersonRepository(db: store.db)
    let ledger = GRDBPlayLedgerRepository(db: store.db)

    let ana = Person(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!, name: "Ana")
    let game = Game(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Jaipur", minimumPlayers: 2, maximumPlayers: 2)
    try people.save(ana)
    try games.save(game)
    let original = PlayEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
        gameID: game.id,
        occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
        participants: [PlayParticipant(personID: ana.id, rating: Rating(rawValue: 5))]
    )
    let correction = PlayEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
        gameID: game.id,
        occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
        participants: [PlayParticipant(personID: ana.id, rating: Rating(rawValue: 4))],
        correctionOf: original.id
    )
    try ledger.append(original)
    try ledger.append(correction)

    let snapshot = try store.snapshot()
    #expect(snapshot.games == [game])
    #expect(snapshot.people == [ana])
    // BOTH the superseded original and the correction are in the snapshot.
    #expect(snapshot.playEvents == [original, correction])
}

@Test("backup file -> restore into an empty store reproduces the exact snapshot")
func backupRestoreRoundTrip() throws {
    let source = try CrateStore.inMemory()
    let games = GRDBGameRepository(db: source.db)
    let people = GRDBPersonRepository(db: source.db)
    let ledger = GRDBPlayLedgerRepository(db: source.db)

    let ana = Person(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!, name: "Ana")
    let bo = Person(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000b")!, name: "Bo")
    let jaipur = Game(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Jaipur", minimumPlayers: 2, maximumPlayers: 2, playTimeMinutes: 30, categories: ["card"])
    let twist = Game(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "Twister, the \"Movie\" Game", categories: ["party"])
    try [ana, bo].forEach { try people.save($0) }
    try [jaipur, twist].forEach { try games.save($0) }
    let p1 = PlayEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!, gameID: jaipur.id, occurredAt: Date(timeIntervalSince1970: 1_700_000_000), participants: [PlayParticipant(personID: ana.id, rating: Rating(rawValue: 5)), PlayParticipant(personID: bo.id)])
    let p2 = PlayEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, gameID: twist.id, occurredAt: nil, participants: [PlayParticipant(personID: bo.id, rating: Rating(rawValue: 2), notes: "rainy")])
    try ledger.append(p1)
    try ledger.append(p2)

    let file = try BackupCodec.encode(snapshot: try source.snapshot(), appVersion: "1.0.0")
    let decoded = try BackupCodec.decode(file)

    let target = try CrateStore.inMemory()
    try target.restore(decoded)
    #expect(try target.snapshot() == decoded)
}

@Test("restore replaces existing data atomically; a rejected file leaves the store untouched")
func restoreCancelSafety() throws {
    let store = try CrateStore.inMemory()
    let games = GRDBGameRepository(db: store.db)
    let people = GRDBPersonRepository(db: store.db)
    let existing = Game(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Keep Me")
    let keeper = Person(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!, name: "Ana")
    try games.save(existing)
    try people.save(keeper)
    let before = try store.snapshot()

    // A snapshot whose play references a game that does not exist must be
    // rejected BEFORE any mutation — the store stays byte-for-byte the same.
    let dangling = BackupCodec.Snapshot(
        games: [Game(id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!, title: "Alien")],
        people: [],
        playEvents: [PlayEvent(gameID: UUID(uuidString: "00000000-0000-0000-0000-000000000077")!)]
    )
    #expect(throws: CrateStore.RestoreError.playReferencesUnknownGame(UUID(uuidString: "00000000-0000-0000-0000-000000000077")!)) {
        try store.restore(dangling)
    }
    #expect(try store.snapshot() == before)

    // Dangling participant reference: same guarantee.
    let danglingPerson = BackupCodec.Snapshot(
        games: [existing],
        people: [],
        playEvents: [PlayEvent(gameID: existing.id, participants: [PlayParticipant(personID: keeper.id)])]
    )
    #expect(throws: CrateStore.RestoreError.participantReferencesUnknownPerson(keeper.id)) {
        try store.restore(danglingPerson)
    }
    #expect(try store.snapshot() == before)

    // Ledger-replay violation (duplicate event id): still untouched.
    let dup = PlayEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!, gameID: existing.id)
    let duplicateHistory = BackupCodec.Snapshot(games: [existing], people: [keeper], playEvents: [dup, dup])
    _ = try? store.restore(duplicateHistory) // throws
    #expect(try store.snapshot() == before)
}

@Test("restore with a valid file wipes and replaces everything")
func restoreReplacesEverything() throws {
    let store = try CrateStore.inMemory()
    let games = GRDBGameRepository(db: store.db)
    let people = GRDBPersonRepository(db: store.db)
    try games.save(Game(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Old Game"))
    try people.save(Person(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!, name: "Old Person"))

    let replacement = BackupCodec.Snapshot(
        games: [Game(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "New Game")],
        people: [Person(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000b")!, name: "New Person")],
        playEvents: []
    )
    try store.restore(replacement)
    let after = try store.snapshot()
    #expect(after == replacement)
}

@Test("restore preserves append-only history: superseded originals and corrections survive")
func restorePreservesLedgerHistory() throws {
    let source = try CrateStore.inMemory()
    let games = GRDBGameRepository(db: source.db)
    let people = GRDBPersonRepository(db: source.db)
    let ledger = GRDBPlayLedgerRepository(db: source.db)
    let ana = Person(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!, name: "Ana")
    let game = Game(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Jaipur")
    try people.save(ana)
    try games.save(game)
    let original = PlayEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!, gameID: game.id, occurredAt: Date(timeIntervalSince1970: 5), participants: [PlayParticipant(personID: ana.id, rating: Rating(rawValue: 5))])
    let correction = PlayEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, gameID: game.id, occurredAt: Date(timeIntervalSince1970: 5), participants: [PlayParticipant(personID: ana.id, rating: Rating(rawValue: 4))], correctionOf: original.id)
    try ledger.append(original)
    try ledger.append(correction)

    let snapshot = try source.snapshot()
    let target = try CrateStore.inMemory()
    try target.restore(snapshot)

    // Raw rows preserved (not just the effective view)...
    #expect(try target.snapshot().playEvents == snapshot.playEvents)
    // ...and effective-event semantics still hold post-restore.
    let restored = PlayLedger(events: try target.snapshot().playEvents)
    #expect(restored.effectiveEvents == [correction])
    // Append-only triggers still reject direct erasure post-restore.
    #expect(throws: (any Error).self) {
        try target.db.write { db in try db.execute(sql: "DELETE FROM plays WHERE id = ?", arguments: [original.id.uuidString]) }
    }
}

@Test("empty snapshot restore wipes the store")
func restoreEmptySnapshot() throws {
    let store = try CrateStore.inMemory()
    let games = GRDBGameRepository(db: store.db)
    try games.save(Game(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Doomed"))
    try store.restore(BackupCodec.Snapshot(games: [], people: [], playEvents: []))
    let empty = try store.snapshot()
    #expect(empty.games.isEmpty)
    #expect(empty.people.isEmpty)
    #expect(empty.playEvents.isEmpty)
}

@Test("migration-from-old-version stub: schema v1 is frozen; the codec accepts only v>=1<=current")
func frozenSchemaV1Stub() throws {
    // The v1 SQLite schema itself has no legacy predecessor yet. When one
    // is introduced, this test is the seam: files stamped below the floor
    // (or above the ceiling) must be refused by the codec BEFORE the store
    // is touched, so no partial migration can happen.
    let store = try CrateStore.inMemory()
    let file = try BackupCodec.encode(snapshot: BackupCodec.Snapshot(games: [], people: [], playEvents: []), appVersion: "1.0.0")
    let envelope = try JSONDecoder().decode(BackupCodec.Envelope.self, from: file)
    #expect(envelope.schemaVersion == 1)
    // Restoring the empty v1 envelope keeps applied migrations at exactly v1.
    try store.restore(try BackupCodec.decode(file))
    let applied = try store.db.read { db in try CrateStoreSchema.migrator.appliedMigrations(db) }
    #expect(applied == ["v1"])
}
