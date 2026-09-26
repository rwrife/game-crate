import Foundation

/// A user-owned category tag attached to a game on the shelf.
public struct CategoryTag: Sendable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { rawValue }
}

/// An integer rating strictly between 1 and 5 stars.
public struct Rating: Sendable, Hashable, Codable, Comparable, RawRepresentable {
    public let rawValue: Int

    public init?(rawValue: Int) {
        guard (1...5).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public static func < (lhs: Rating, rhs: Rating) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A person in the player roster.
public struct Person: Sendable, Hashable, Identifiable, Codable {
    public let id: UUID
    public var name: String
    public var createdAt: Date?
    public var notes: String?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.notes = notes
    }
}

/// A game on the shelf with optional range/time fields.
/// Absence is strictly unknown, never inferred or defaulted.
public struct Game: Sendable, Hashable, Identifiable, Codable {
    public let id: UUID
    public var title: String
    public var minimumPlayers: Int?
    public var maximumPlayers: Int?
    public var playTimeMinutes: Int?
    public var categories: [CategoryTag]
    public var createdAt: Date?
    public var notes: String?

    public init(
        id: UUID = UUID(),
        title: String,
        minimumPlayers: Int? = nil,
        maximumPlayers: Int? = nil,
        playTimeMinutes: Int? = nil,
        categories: [CategoryTag] = [],
        createdAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.minimumPlayers = minimumPlayers
        self.maximumPlayers = maximumPlayers
        self.playTimeMinutes = playTimeMinutes
        self.categories = categories
        self.createdAt = createdAt
        self.notes = notes
    }
}

/// A participant in a play session with an optional per-player rating.
public struct PlayParticipant: Sendable, Hashable, Codable {
    public let personID: UUID
    public var rating: Rating?
    public var notes: String?

    public init(
        personID: UUID,
        rating: Rating? = nil,
        notes: String? = nil
    ) {
        self.personID = personID
        self.rating = rating
        self.notes = notes
    }
}
