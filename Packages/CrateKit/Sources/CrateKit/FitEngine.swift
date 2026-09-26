import Foundation

/// A player-count / time-budget / category query against the shelf.
public struct FitQuery: Sendable, Hashable {
    public var playerCount: Int
    public var timeBudgetMinutes: Int
    public var requiredCategories: [CategoryTag]

    public init(
        playerCount: Int,
        timeBudgetMinutes: Int,
        requiredCategories: [CategoryTag] = []
    ) {
        self.playerCount = playerCount
        self.timeBudgetMinutes = timeBudgetMinutes
        self.requiredCategories = requiredCategories
    }
}

/// A single named reason a known game did not fit a query.
/// Every exclusion is explainable — no silent drops.
public enum ExclusionReason: Sendable, Hashable {
    case tooFewPlayers(minimum: Int, requested: Int)
    case tooManyPlayers(maximum: Int, requested: Int)
    case exceedsTimeBudget(gameMinutes: Int, budgetMinutes: Int)
    case missingCategory([CategoryTag])
}

/// A game that was evaluated but excluded, with every reason it failed.
public struct FitExclusion: Sendable, Hashable {
    public let game: Game
    public let reasons: [ExclusionReason]
}

/// A game accepted onto tonight's shortlist.
public struct ShortlistEntry: Sendable, Hashable {
    public let game: Game
    /// Integer days since the most recent dated play, or `nil` if the game
    /// has never been played (or every play has an unrecorded date) — the
    /// most "overdue" state, ranked first.
    public let daysSinceLastPlay: Int?
    /// Sum and count of integer ratings across recorded plays, kept as
    /// integers so ranking never performs floating-point comparisons.
    public let ratingSum: Int
    public let ratingCount: Int
}

/// The outcome of evaluating the shelf against a `FitQuery`.
public struct FitResult: Sendable, Hashable {
    public let shortlist: [ShortlistEntry]
    public let exclusions: [FitExclusion]
    /// Games with unknown player range or time (never silently included or
    /// excluded); always tracked separately.
    public let unspecifiedGames: [Game]

    public var unspecifiedCount: Int { unspecifiedGames.count }
}

/// Deterministic, explainable fit engine: ranks a shortlist for tonight and
/// names every exclusion reason. Never infers unknown fields.
public struct FitEngine: Sendable {
    public init() {}

    public func evaluate(
        games: [Game],
        ledger: PlayLedger,
        asOf: Date,
        query: FitQuery,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> FitResult {
        var shortlistCandidates: [ShortlistEntry] = []
        var exclusions: [FitExclusion] = []
        var unspecifiedGames: [Game] = []

        for game in games {
            guard
                let minimumPlayers = game.minimumPlayers,
                let maximumPlayers = game.maximumPlayers,
                let playTimeMinutes = game.playTimeMinutes
            else {
                unspecifiedGames.append(game)
                continue
            }

            var reasons: [ExclusionReason] = []

            if query.playerCount < minimumPlayers {
                reasons.append(.tooFewPlayers(minimum: minimumPlayers, requested: query.playerCount))
            }
            if query.playerCount > maximumPlayers {
                reasons.append(.tooManyPlayers(maximum: maximumPlayers, requested: query.playerCount))
            }
            if playTimeMinutes > query.timeBudgetMinutes {
                reasons.append(.exceedsTimeBudget(gameMinutes: playTimeMinutes, budgetMinutes: query.timeBudgetMinutes))
            }
            if !query.requiredCategories.isEmpty {
                let missing = query.requiredCategories.filter { !game.categories.contains($0) }
                if !missing.isEmpty {
                    reasons.append(.missingCategory(missing))
                }
            }

            if reasons.isEmpty {
                let plays = playEvents(for: game.id, in: ledger)
                let daysSinceLastPlay = Derivations.daysSinceLastPlay(plays: plays, asOf: asOf, calendar: calendar)
                let (sum, count) = ratingTotals(plays: plays)
                shortlistCandidates.append(
                    ShortlistEntry(game: game, daysSinceLastPlay: daysSinceLastPlay, ratingSum: sum, ratingCount: count)
                )
            } else {
                exclusions.append(FitExclusion(game: game, reasons: reasons))
            }
        }

        let shortlist = shortlistCandidates.sorted { lhs, rhs in
            Self.isRankedBefore(lhs, rhs)
        }

        return FitResult(shortlist: shortlist, exclusions: exclusions, unspecifiedGames: unspecifiedGames)
    }

    /// Ranking order: longest since last play first (never-played/undated
    /// sorts first as "most overdue"), then higher average rating, then
    /// title ascending. Rating comparison uses integer cross-multiplication
    /// (`sumA * countB` vs `sumB * countA`) so no floating-point division
    /// ever enters the tie-break.
    static func isRankedBefore(_ lhs: ShortlistEntry, _ rhs: ShortlistEntry) -> Bool {
        let lhsRecency = lhs.daysSinceLastPlay ?? Int.max
        let rhsRecency = rhs.daysSinceLastPlay ?? Int.max
        if lhsRecency != rhsRecency {
            return lhsRecency > rhsRecency
        }

        let crossLeft = lhs.ratingSum * rhs.ratingCount
        let crossRight = rhs.ratingSum * lhs.ratingCount
        if crossLeft != crossRight {
            return crossLeft > crossRight
        }

        return lhs.game.title < rhs.game.title
    }

    private func playEvents(for gameID: UUID, in ledger: PlayLedger) -> [PlayEvent] {
        ledger.effectiveEvents.filter { $0.gameID == gameID }
    }

    private func ratingTotals(plays: [PlayEvent]) -> (sum: Int, count: Int) {
        var sum = 0
        var count = 0
        for play in plays {
            for participant in play.participants {
                if let rating = participant.rating {
                    sum += rating.rawValue
                    count += 1
                }
            }
        }
        return (sum, count)
    }
}
