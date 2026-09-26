import Foundation
import Testing
@testable import CrateKit

@Suite("Derivations: calendar-safe recency and count-based insight")
struct DerivationsTests {
    private let utc = Calendar(identifier: .gregorian)

    @Test("days since last play counts calendar days, not 24-hour periods")
    func calendarDayCounting() {
        // 23:00 on day D -> 01:00 on day D+2 is 2 calendar days even though
        // only ~26 hours elapsed.
        let last = utc.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 23))!
        let asOf = utc.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 1))!
        let plays = [PlayEvent(id: UUID(1), gameID: UUID(10), occurredAt: last)]

        #expect(Derivations.daysSinceLastPlay(plays: plays, asOf: asOf, calendar: utc) == 2)
    }

    @Test("DST spring-forward boundary still yields one calendar day")
    func dstSpringForward() throws {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // 2026-03-08 is US spring-forward day: 2am skips to 3am.
        let last = try #require(ny.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 20)))
        let asOf = try #require(ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 20)))
        let plays = [PlayEvent(id: UUID(1), gameID: UUID(10), occurredAt: last)]

        // Only 23 real hours elapsed, but calendar day difference is exactly 1.
        #expect(Derivations.daysSinceLastPlay(plays: plays, asOf: asOf, calendar: ny) == 1)
    }

    @Test("DST fall-back boundary still yields one calendar day")
    func dstFallBack() throws {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // 2026-11-01 is US fall-back day: the 25-hour gap must not round up.
        let last = try #require(ny.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 20)))
        let asOf = try #require(ny.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 20)))
        let plays = [PlayEvent(id: UUID(1), gameID: UUID(10), occurredAt: last)]

        #expect(Derivations.daysSinceLastPlay(plays: plays, asOf: asOf, calendar: ny) == 1)
    }

    @Test("pre-1970 play dates produce a correct positive day count")
    func preEpochDates() throws {
        var calendar = utc
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let last = calendar.date(from: DateComponents(year: 1969, month: 12, day: 30, hour: 12))!
        let asOf = calendar.date(from: DateComponents(year: 1970, month: 1, day: 2, hour: 12))!
        let plays = [PlayEvent(id: UUID(1), gameID: UUID(10), occurredAt: last)]

        #expect(Derivations.daysSinceLastPlay(plays: plays, asOf: asOf, calendar: calendar) == 3)
    }

    @Test("absent dates and empty ledgers return unknown instead of guessing")
    func absentDatesAreUnknown() {
        let undated = [PlayEvent(id: UUID(1), gameID: UUID(10), occurredAt: nil)]
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(Derivations.daysSinceLastPlay(plays: [], asOf: asOf, calendar: utc) == nil)
        #expect(Derivations.daysSinceLastPlay(plays: undated, asOf: asOf, calendar: utc) == nil)
    }

    @Test("plays per game counts only effective (non-corrected) events")
    func playsPerGame() {
        let gameA = UUID(1)
        let gameB = UUID(2)
        let original = PlayEvent(id: UUID(101), gameID: gameA, occurredAt: Date(timeIntervalSince1970: 1_000))
        let correction = PlayEvent(id: UUID(102), gameID: gameA, occurredAt: Date(timeIntervalSince1970: 2_000), correctionOf: original.id)
        let other = PlayEvent(id: UUID(103), gameID: gameB, occurredAt: Date(timeIntervalSince1970: 3_000))
        let ledger = PlayLedger(events: [original, correction, other])

        let counts = Derivations.playsPerGame(ledger: ledger, games: [
            Game(id: gameA, title: "A"),
            Game(id: gameB, title: "B"),
            Game(id: UUID(3), title: "Unplayed"),
        ])

        #expect(counts == [gameA: 1, gameB: 1, UUID(3): 0])
    }

    @Test("per-player counts aggregate ratings and categories as integers")
    func perPlayerCounts() {
        let alice = UUID(201)
        let blue = UUID(202)
        let coop = CategoryTag("Cooperative")
        let party = CategoryTag("Party")
        let coopGame = Game(id: UUID(1), title: "Pandemic", categories: [coop])
        let partyGame = Game(id: UUID(2), title: "Codenames", categories: [party])

        let ledger = PlayLedger(events: [
            PlayEvent(id: UUID(101), gameID: coopGame.id, occurredAt: nil, participants: [
                .init(personID: alice, rating: Rating(rawValue: 5)),
                .init(personID: blue, rating: Rating(rawValue: 2)),
            ]),
            PlayEvent(id: UUID(102), gameID: partyGame.id, occurredAt: nil, participants: [
                .init(personID: alice),
                .init(personID: blue, rating: Rating(rawValue: 4)),
            ]),
            PlayEvent(id: UUID(103), gameID: coopGame.id, occurredAt: nil, participants: [
                .init(personID: alice, rating: Rating(rawValue: 4)),
            ]),
        ])

        let profile = Derivations.playerProfile(personID: alice, ledger: ledger, games: [coopGame, partyGame])

        #expect(profile.playCount == 3)
        #expect(profile.ratingCount == 2)
        #expect(profile.ratingSum == 9)
        #expect(profile.ratingDistribution == [4: 1, 5: 1])
        #expect(profile.categoryCounts == [coop: 2, party: 1])
    }

    @Test("insufficient history yields zero counts, never interpolated stats")
    func insufficientHistory() {
        let profile = Derivations.playerProfile(personID: UUID(201), ledger: PlayLedger(), games: [])

        #expect(profile.playCount == 0)
        #expect(profile.ratingCount == 0)
        #expect(profile.ratingSum == 0)
        #expect(profile.ratingDistribution.isEmpty)
        #expect(profile.categoryCounts.isEmpty)
    }

    @Test("coverage holes name user tag/range gaps and respect unknowns")
    func coverageHoles() {
        let twoPlayerQuick = Game(id: UUID(1), title: "Jaipur", minimumPlayers: 2, maximumPlayers: 2, playTimeMinutes: 30, categories: [.init("Card")])
        let unknownGame = Game(id: UUID(2), title: "Blank")
        let hole = ShelfHole(minPlayers: 2, maxPlayers: 2, maxMinutes: 30)

        let matches = Derivations.gamesFitting(hole: hole, games: [twoPlayerQuick])
        let holes = Derivations.coverageHoles(requested: [hole], games: [twoPlayerQuick, unknownGame])

        #expect(matches == [twoPlayerQuick.id])
        #expect(holes.count == 1)
        #expect(holes[0].hole == hole)
        #expect(holes[0].matchingGameCount == 1)
    }
}
