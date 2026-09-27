import Foundation
import CrateKit
import CrateStore

/// Thread-safe fakes for previews and UI tests. Each instance owns its own state.
public final class InMemoryGameRepository: GameRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: Game]
    public init(games: [Game] = []) { values = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) }) }
    public func save(_ game: Game) throws { lock.withLock { values[game.id] = game } }
    public func game(id: UUID) throws -> Game? { lock.withLock { values[id] } }
    public func allGames() throws -> [Game] { lock.withLock { values.values.sorted { ($0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending) } } }
    public func deleteGame(id: UUID) throws { _ = lock.withLock { values.removeValue(forKey: id) } }
}

public final class InMemoryPersonRepository: PersonRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: Person]
    public init(people: [Person] = []) { values = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) }) }
    public func save(_ person: Person) throws { lock.withLock { values[person.id] = person } }
    public func person(id: UUID) throws -> Person? { lock.withLock { values[id] } }
    public func allPeople() throws -> [Person] { lock.withLock { values.values.sorted { ($0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending) } } }
    public func deletePerson(id: UUID) throws { _ = lock.withLock { values.removeValue(forKey: id) } }
}

public final class InMemoryPlayLedgerRepository: PlayLedgerRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var ledger: PlayLedger
    public init(events: [PlayEvent] = []) { ledger = PlayLedger(events: events) }
    public func append(_ event: PlayEvent) throws { try lock.withLock { try ledger.append(event) } }
    public func events(for gameID: UUID) throws -> [PlayEvent] { lock.withLock { ledger.events.filter { $0.gameID == gameID } } }
}
