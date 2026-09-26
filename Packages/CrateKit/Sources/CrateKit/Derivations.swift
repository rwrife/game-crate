import Foundation

/// Integer-only count summary for one player's recorded history.
public struct PlayerProfileCounts: Sendable, Hashable {
    public let playCount: Int
    public let ratingCount: Int
    public let ratingSum: Int
    public let ratingDistribution: [Int: Int]
    public let categoryCounts: [CategoryTag: Int]
}

/// A user-requested coverage shape used to ask what the shelf lacks.
public struct ShelfHole: Sendable, Hashable {
    public let minPlayers: Int
    public let maxPlayers: Int
    public let maxMinutes: Int
    public let category: CategoryTag?

    public init(
        minPlayers: Int,
        maxPlayers: Int,
        maxMinutes: Int,
        category: CategoryTag? = nil
    ) {
        self.minPlayers = minPlayers
        self.maxPlayers = maxPlayers
        self.maxMinutes = maxMinutes
        self.category = category
    }
}

/// Explainable shelf coverage result. Unknown game fields never count as a
/// match because the engine cannot prove coverage from absent data.
public struct ShelfCoverage: Sendable, Hashable {
    public let hole: ShelfHole
    public let matchingGameCount: Int
    public let unspecifiedGameCount: Int
}

/// Pure count and calendar derivations from shelf + append-only ledger state.
public enum Derivations {
    /// Calendar-day difference from the latest dated play. This deliberately
    /// compares each day's start rather than dividing seconds by 86,400, so
    /// DST transitions remain correct. Returns nil when no date is known.
    public static func daysSinceLastPlay(
        plays: [PlayEvent],
        asOf: Date,
        calendar: Calendar
    ) -> Int? {
        guard let latest = plays.compactMap(\.occurredAt).max() else { return nil }
        let latestDay = calendar.startOfDay(for: latest)
        let asOfDay = calendar.startOfDay(for: asOf)
        return calendar.dateComponents([.day], from: latestDay, to: asOfDay).day
    }

    /// Number of effective plays for every requested game, including zeros.
    public static func playsPerGame(ledger: PlayLedger, games: [Game]) -> [UUID: Int] {
        var result = Dictionary(uniqueKeysWithValues: games.map { ($0.id, 0) })
        for play in ledger.effectiveEvents where result[play.gameID] != nil {
            result[play.gameID, default: 0] += 1
        }
        return result
    }

    /// Count-only profile data. No interpolation, labels, averages, or model
    /// output; absent history is represented by zero/empty counts.
    public static func playerProfile(
        personID: UUID,
        ledger: PlayLedger,
        games: [Game]
    ) -> PlayerProfileCounts {
        let gamesByID = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })
        var playCount = 0
        var ratingCount = 0
        var ratingSum = 0
        var distribution: [Int: Int] = [:]
        var categoryCounts: [CategoryTag: Int] = [:]

        for play in ledger.effectiveEvents {
            guard let participant = play.participants.first(where: { $0.personID == personID }) else {
                continue
            }
            playCount += 1
            if let rating = participant.rating {
                ratingCount += 1
                ratingSum += rating.rawValue
                distribution[rating.rawValue, default: 0] += 1
            }
            if let game = gamesByID[play.gameID] {
                for category in Set(game.categories) {
                    categoryCounts[category, default: 0] += 1
                }
            }
        }

        return PlayerProfileCounts(
            playCount: playCount,
            ratingCount: ratingCount,
            ratingSum: ratingSum,
            ratingDistribution: distribution,
            categoryCounts: categoryCounts
        )
    }

    /// IDs of games proven to cover the requested user-owned shape.
    public static func gamesFitting(hole: ShelfHole, games: [Game]) -> [UUID] {
        games.compactMap { game in
            guard
                let minimum = game.minimumPlayers,
                let maximum = game.maximumPlayers,
                let minutes = game.playTimeMinutes,
                minimum <= hole.minPlayers,
                maximum >= hole.maxPlayers,
                minutes <= hole.maxMinutes
            else {
                return nil
            }
            if let category = hole.category, !game.categories.contains(category) {
                return nil
            }
            return game.id
        }
    }

    /// Coverage results for user-requested shapes. The caller decides which
    /// zero-count entries to present as actual holes.
    public static func coverageHoles(requested: [ShelfHole], games: [Game]) -> [ShelfCoverage] {
        let unspecifiedCount = games.filter {
            $0.minimumPlayers == nil || $0.maximumPlayers == nil || $0.playTimeMinutes == nil
        }.count

        return requested.map { hole in
            ShelfCoverage(
                hole: hole,
                matchingGameCount: gamesFitting(hole: hole, games: games).count,
                unspecifiedGameCount: unspecifiedCount
            )
        }
    }
}
