import Foundation
import Testing
@testable import CrateKit

@Suite("Domain models and append-only ledger")
struct DomainModelTests {
    @Test("games preserve unknown fit fields")
    func gameUnknowns() {
        let game = Game(id: UUID(0), title: "Mystery", categories: [.init("Cards")])

        #expect(game.minimumPlayers == nil)
        #expect(game.maximumPlayers == nil)
        #expect(game.playTimeMinutes == nil)
        #expect(game.categories == [.init("Cards")])
    }

    @Test("ratings accept only integers from one through five", arguments: [-1, 0, 1, 3, 5, 6])
    func ratingBounds(rawValue: Int) {
        let rating = Rating(rawValue: rawValue)
        #expect((rating != nil) == (1...5).contains(rawValue))
    }

    @Test("corrections append a compensating event and preserve the original")
    func correctionsAreAppendOnly() throws {
        let original = PlayEvent(
            id: UUID(1),
            gameID: UUID(10),
            occurredAt: Date(timeIntervalSince1970: 1_000),
            participants: [.init(personID: UUID(20), rating: Rating(rawValue: 3))]
        )
        var ledger = PlayLedger(events: [original])
        let replacement = PlayEvent(
            id: UUID(2),
            gameID: original.gameID,
            occurredAt: Date(timeIntervalSince1970: 2_000),
            participants: [.init(personID: UUID(20), rating: Rating(rawValue: 5))],
            correctionOf: original.id
        )

        try ledger.append(replacement)

        #expect(ledger.events == [original, replacement])
        #expect(ledger.effectiveEvents == [replacement])
    }

    @Test("correction must reference an existing effective event")
    func correctionReferenceValidation() {
        var ledger = PlayLedger()
        let orphan = PlayEvent(
            id: UUID(2),
            gameID: UUID(10),
            occurredAt: nil,
            correctionOf: UUID(99)
        )

        #expect(throws: PlayLedgerError.correctedEventNotFound(UUID(99))) {
            try ledger.append(orphan)
        }
        #expect(ledger.events.isEmpty)
    }

    @Test("duplicate event identifiers are rejected")
    func duplicateIDs() throws {
        let event = PlayEvent(id: UUID(1), gameID: UUID(10), occurredAt: nil)
        var ledger = PlayLedger(events: [event])

        #expect(throws: PlayLedgerError.duplicateEventID(event.id)) {
            try ledger.append(event)
        }
        #expect(ledger.events == [event])
    }
}
