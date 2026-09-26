import Foundation

/// Append-only errors raised when mutating a `PlayLedger`.
public enum PlayLedgerError: Error, Equatable, Sendable {
    case duplicateEventID(UUID)
    case correctedEventNotFound(UUID)
    case gameMismatch(expected: UUID, actual: UUID)
}

/// An immutable play event recorded in the append-only ledger.
/// Corrections are compensating events referencing `correctionOf`,
/// never in-place rewrites.
public struct PlayEvent: Sendable, Hashable, Identifiable, Codable {
    public let id: UUID
    public let gameID: UUID
    public let occurredAt: Date?
    public let participants: [PlayParticipant]
    public let notes: String?
    public let correctionOf: UUID?

    public init(
        id: UUID = UUID(),
        gameID: UUID,
        occurredAt: Date? = nil,
        participants: [PlayParticipant] = [],
        notes: String? = nil,
        correctionOf: UUID? = nil
    ) {
        self.id = id
        self.gameID = gameID
        self.occurredAt = occurredAt
        self.participants = participants
        self.notes = notes
        self.correctionOf = correctionOf
    }
}

/// An append-only ledger of play events.
public struct PlayLedger: Sendable, Hashable, Codable {
    public private(set) var events: [PlayEvent]

    public init(events: [PlayEvent] = []) {
        self.events = events
    }

    /// Appends a new event or compensating correction.
    public mutating func append(_ event: PlayEvent) throws {
        guard !events.contains(where: { $0.id == event.id }) else {
            throw PlayLedgerError.duplicateEventID(event.id)
        }

        if let correctionOf = event.correctionOf {
            let effective = effectiveEvents
            guard let target = effective.first(where: { $0.id == correctionOf }) else {
                throw PlayLedgerError.correctedEventNotFound(correctionOf)
            }
            guard target.gameID == event.gameID else {
                throw PlayLedgerError.gameMismatch(expected: target.gameID, actual: event.gameID)
            }
        }

        events.append(event)
    }

    /// Current effective events after applying compensating corrections.
    public var effectiveEvents: [PlayEvent] {
        var superseded = Set<UUID>()
        for event in events {
            if let target = event.correctionOf {
                superseded.insert(target)
            }
        }
        return events.filter { !superseded.contains($0.id) }
    }
}
