import Foundation
import GRDB
import CrateKit

/// Whole-store capture and atomic replace for backup/restore (issue #7).
///
/// - `snapshot` reads every row: games, people, and the COMPLETE ledger
///   history (superseded originals included), so the append-only record
///   survives a backup/restore cycle unchanged.
/// - `restore` replaces all data inside ONE transaction: it rolls back
///   entirely on any failure, so a rejected file leaves the store exactly
///   as it was. All validation happens BEFORE the destructive pass:
///   referential checks plus a pure `PlayLedger` replay (duplicate ids,
///   dangling or duplicate corrections, correction game-mismatch). Deleting
///   games/people cascades the ledger — the v1 append-only triggers allow
///   cascade, only direct play/rating erasure and in-place updates are
///   forbidden, which is why the restore inserts complete rows instead of
///   updating. Events may only reference history that precedes them (the
///   ledger replay proves it), so `correction_of` inserts directly.
public extension CrateStore {
    enum RestoreError: Error, Equatable, Sendable {
        case playReferencesUnknownGame(UUID)
        case participantReferencesUnknownPerson(UUID)
        case invalidLedgerHistory(String)
    }

    func snapshot() throws -> BackupCodec.Snapshot {
        try db.read { db in
            BackupCodec.Snapshot(
                games: try GRDBGameRepository.allGames(in: db),
                people: try GRDBPersonRepository.allPeople(in: db),
                // Stable global order: games by title, events by insertion.
                playEvents: try GRDBPlayLedgerRepository.allEvents(in: db)
            )
        }
    }

    func restore(_ snapshot: BackupCodec.Snapshot) throws {
        // 1. Referential pre-check: reject before touching anything.
        let gameIDs = Set(snapshot.games.map(\.id))
        let personIDs = Set(snapshot.people.map(\.id))
        for event in snapshot.playEvents {
            guard gameIDs.contains(event.gameID) else {
                throw RestoreError.playReferencesUnknownGame(event.gameID)
            }
            for participant in event.participants {
                guard personIDs.contains(participant.personID) else {
                    throw RestoreError.participantReferencesUnknownPerson(participant.personID)
                }
            }
        }

        // 2. Domain replay: duplicates, dangling/double corrections, and
        //    correction game-mismatch all fail here, before any mutation.
        do {
            var ledger = PlayLedger()
            for event in snapshot.playEvents {
                try ledger.append(event)
            }
        } catch {
            throw RestoreError.invalidLedgerHistory(String(describing: error))
        }

        // 3. Atomic replace. `db.write` wraps its body in a transaction, so
        //    any throw (including FK violations) rolls the store back.
        try db.write { db in
            try db.execute(sql: "DELETE FROM games")   // cascades plays + ratings
            try db.execute(sql: "DELETE FROM people")  // cascades ratings
            for game in snapshot.games { try GRDBGameRepository.insert(game, in: db) }
            for person in snapshot.people { try GRDBPersonRepository.insert(person, in: db) }
            for event in snapshot.playEvents { try GRDBPlayLedgerRepository.insert(event, in: db) }
        }
    }
}
