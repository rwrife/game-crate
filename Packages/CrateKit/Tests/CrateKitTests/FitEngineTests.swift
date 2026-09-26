import Foundation
import Testing
@testable import CrateKit

@Suite("Fit engine shortlist and exclusion explainability")
struct FitEngineTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("shortlist includes games matching player count and time budget")
    func shortlistMatchingGame() {
        let game = Game(
            id: UUID(1),
            title: "Azul",
            minimumPlayers: 2,
            maximumPlayers: 4,
            playTimeMinutes: 45,
            categories: [.init("Abstract"), .init("Drafting")]
        )
        let engine = FitEngine()
        let query = FitQuery(playerCount: 3, timeBudgetMinutes: 60)

        let result = engine.evaluate(games: [game], ledger: PlayLedger(), asOf: now, query: query)

        #expect(result.shortlist.map(\.game.id) == [game.id])
        #expect(result.exclusions.isEmpty)
        #expect(result.unspecifiedCount == 0)
    }

    @Test("games missing player range or time budget are marked unspecified and never shortlisted")
    func unknownsAreUnspecified() {
        let missingPlayers = Game(id: UUID(1), title: "No Range", minimumPlayers: nil, maximumPlayers: nil, playTimeMinutes: 30)
        let missingTime = Game(id: UUID(2), title: "No Time", minimumPlayers: 2, maximumPlayers: 4, playTimeMinutes: nil)
        let bothUnknown = Game(id: UUID(3), title: "Blank")

        let engine = FitEngine()
        let query = FitQuery(playerCount: 3, timeBudgetMinutes: 45)
        let result = engine.evaluate(games: [missingPlayers, missingTime, bothUnknown], ledger: PlayLedger(), asOf: now, query: query)

        #expect(result.shortlist.isEmpty)
        #expect(result.exclusions.isEmpty)
        #expect(result.unspecifiedCount == 3)
        #expect(result.unspecifiedGames.map(\.id) == [missingPlayers.id, missingTime.id, bothUnknown.id])
    }

    @Test("named exclusions explain why a known game did not fit")
    func namedExclusions() {
        let tooFew = Game(id: UUID(1), title: "Solo Only", minimumPlayers: 1, maximumPlayers: 1, playTimeMinutes: 20, categories: [.init("Strategy")])
        let tooMany = Game(id: UUID(2), title: "Group Only", minimumPlayers: 5, maximumPlayers: 8, playTimeMinutes: 30, categories: [.init("Strategy")])
        let tooLong = Game(id: UUID(3), title: "Epic", minimumPlayers: 2, maximumPlayers: 4, playTimeMinutes: 120, categories: [.init("Strategy")])
        let wrongCategory = Game(id: UUID(4), title: "Dice Game", minimumPlayers: 2, maximumPlayers: 4, playTimeMinutes: 30, categories: [.init("Dice")])

        let engine = FitEngine()
        let query = FitQuery(playerCount: 3, timeBudgetMinutes: 45, requiredCategories: [.init("Strategy")])
        let result = engine.evaluate(games: [tooFew, tooMany, tooLong, wrongCategory], ledger: PlayLedger(), asOf: now, query: query)

        #expect(result.shortlist.isEmpty)
        let exclusionMap = Dictionary(uniqueKeysWithValues: result.exclusions.map { ($0.game.id, $0.reasons) })
        #expect(exclusionMap[tooFew.id] == [.tooManyPlayers(maximum: 1, requested: 3)])
        #expect(exclusionMap[tooMany.id] == [.tooFewPlayers(minimum: 5, requested: 3)])
        #expect(exclusionMap[tooLong.id] == [.exceedsTimeBudget(gameMinutes: 120, budgetMinutes: 45)])
        #expect(exclusionMap[wrongCategory.id] == [.missingCategory([.init("Strategy")])])
    }

    @Test("shortlist ranks deterministic tie-break: days since last play descending, then average rating descending, then title ascending")
    func rankingTieBreakers() {
        let gameA = Game(id: UUID(1), title: "Catan", minimumPlayers: 3, maximumPlayers: 4, playTimeMinutes: 60)
        let gameB = Game(id: UUID(2), title: "Ticket to Ride", minimumPlayers: 2, maximumPlayers: 5, playTimeMinutes: 60)
        let gameC = Game(id: UUID(3), title: "Pandemic", minimumPlayers: 2, maximumPlayers: 4, playTimeMinutes: 45)

        // gameA played 30 days ago, rated 4.
        // gameB played 10 days ago, rated 5.
        // gameC never played (infinite recency wait), rated 3.
        let day: TimeInterval = 86_400
        let eventA = PlayEvent(
            id: UUID(101),
            gameID: gameA.id,
            occurredAt: now.addingTimeInterval(-30 * day),
            participants: [.init(personID: UUID(201), rating: Rating(rawValue: 4))]
        )
        let eventB = PlayEvent(
            id: UUID(102),
            gameID: gameB.id,
            occurredAt: now.addingTimeInterval(-10 * day),
            participants: [.init(personID: UUID(201), rating: Rating(rawValue: 5))]
        )
        let eventC = PlayEvent(
            id: UUID(103),
            gameID: gameC.id,
            occurredAt: nil, // unrecorded date -> treated as never dated
            participants: [.init(personID: UUID(201), rating: Rating(rawValue: 3))]
        )

        let ledger = PlayLedger(events: [eventA, eventB, eventC])
        let engine = FitEngine()
        let query = FitQuery(playerCount: 3, timeBudgetMinutes: 60)
        let result = engine.evaluate(games: [gameA, gameB, gameC], ledger: ledger, asOf: now, query: query)

        // Never-played/undated ranks first (needs play most), then 30 days ago, then 10 days ago.
        #expect(result.shortlist.map(\.game.id) == [gameC.id, gameA.id, gameB.id])
    }

    @Test("all excluded case reports empty shortlist, zero unspecified, and full exclusion count")
    func allExcluded() {
        let game = Game(id: UUID(1), title: "Long Game", minimumPlayers: 2, maximumPlayers: 2, playTimeMinutes: 180)
        let engine = FitEngine()
        let query = FitQuery(playerCount: 5, timeBudgetMinutes: 60)
        let result = engine.evaluate(games: [game], ledger: PlayLedger(), asOf: now, query: query)

        #expect(result.shortlist.isEmpty)
        #expect(result.unspecifiedCount == 0)
        #expect(result.exclusions.count == 1)
    }

    @Test("all unknown case reports empty shortlist, empty exclusions, and full unspecified count")
    func allUnknown() {
        let game1 = Game(id: UUID(1), title: "One")
        let game2 = Game(id: UUID(2), title: "Two")
        let engine = FitEngine()
        let query = FitQuery(playerCount: 4, timeBudgetMinutes: 60)
        let result = engine.evaluate(games: [game1, game2], ledger: PlayLedger(), asOf: now, query: query)

        #expect(result.shortlist.isEmpty)
        #expect(result.exclusions.isEmpty)
        #expect(result.unspecifiedCount == 2)
    }
}
