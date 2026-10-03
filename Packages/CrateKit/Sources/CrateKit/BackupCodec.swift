import Foundation

/// Versioned, self-verifying JSON backup envelope for the whole crate
/// (issue #7). A backup is a single user-owned file: schema version, app
/// version, timestamp, the complete snapshot, and an integrity digest over
/// the canonical payload. Files written by a newer schema, unreadable
/// payloads, or digest mismatches are rejected with a clear error — never
/// partially imported.
///
/// Contract (issue #7 acceptance):
/// - The envelope is pure Codable JSON; no network access, no proprietary
///   framing. Roundtrip (export → import) must reproduce the store exactly.
/// - Forward-incompatible files (schemaVersion > `currentSchemaVersion`)
///   fail closed with `.schemaTooNew`.
/// - `payloadDigest` is a SHA-256 over the canonical payload JSON; a
///   mismatch (truncated/edited file) fails closed with `.integrityMismatch`.
/// - Dates use `JSONEncoder`/`JSONDecoder`'s default `Date` representation
///   (a JSON number), which round-trips losslessly.
public enum BackupCodec {
    /// Schema version this build writes and can read.
    public static let currentSchemaVersion = 1

    public struct Snapshot: Codable, Sendable, Hashable {
        public var games: [Game]
        public var people: [Person]
        /// ALL ledger events, including superseded originals — the
        /// append-only history is part of the backup, not just the
        /// effective view.
        public var playEvents: [PlayEvent]

        public init(games: [Game], people: [Person], playEvents: [PlayEvent]) {
            self.games = games
            self.people = people
            self.playEvents = playEvents
        }
    }

    public struct Envelope: Codable, Sendable, Hashable {
        public var schemaVersion: Int
        public var appVersion: String
        public var createdAt: Date
        public var payloadDigest: String
        public var snapshot: Snapshot

        public init(schemaVersion: Int, appVersion: String, createdAt: Date, payloadDigest: String, snapshot: Snapshot) {
            self.schemaVersion = schemaVersion
            self.appVersion = appVersion
            self.createdAt = createdAt
            self.payloadDigest = payloadDigest
            self.snapshot = snapshot
        }
    }

    public enum BackupError: Error, Equatable, Sendable {
        case unreadableFile(String)
        case schemaTooNew(found: Int, supported: Int)
        case schemaVersionInvalid(found: Int)
        case integrityMismatch
    }

    /// Canonical payload bytes: sorted keys make the digest stable across
    /// runs and platforms.
    static func canonicalPayload(_ snapshot: Snapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// Serializes a complete backup file for the given crate state.
    public static func encode(
        snapshot: Snapshot,
        appVersion: String,
        createdAt: Date = .now
    ) throws -> Data {
        let payload = try canonicalPayload(snapshot)
        let envelope = Envelope(
            schemaVersion: currentSchemaVersion,
            appVersion: appVersion,
            createdAt: createdAt,
            payloadDigest: SHA256.hexDigest(payload),
            snapshot: snapshot
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(envelope)
    }

    /// Parses and fully validates a backup file BEFORE any caller touches
    /// its own data. Version check first, then payload digest, then the
    /// validated snapshot is handed to the caller.
    public static func decode(_ data: Data) throws -> Snapshot {
        let decoder = JSONDecoder()
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw BackupError.unreadableFile(String(describing: error))
        }
        guard envelope.schemaVersion <= currentSchemaVersion else {
            throw BackupError.schemaTooNew(found: envelope.schemaVersion, supported: currentSchemaVersion)
        }
        guard envelope.schemaVersion >= 1 else {
            throw BackupError.schemaVersionInvalid(found: envelope.schemaVersion)
        }
        let payload = try canonicalPayload(envelope.snapshot)
        guard SHA256.hexDigest(payload) == envelope.payloadDigest else {
            throw BackupError.integrityMismatch
        }
        return envelope.snapshot
    }
}
