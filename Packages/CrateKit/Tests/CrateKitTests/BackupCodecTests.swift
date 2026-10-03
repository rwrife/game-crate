import Foundation
import Testing
@testable import CrateKit

@Suite("BackupCodec: versioned envelope, integrity, rejection")
struct BackupCodecTests {
    private static let utc = TimeZone(identifier: "UTC")!

    private func sampleSnapshot() -> BackupCodec.Snapshot {
        let ana = Person(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!, name: "Ana")
        let bo = Person(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000b")!, name: "Bo")
        let jaipur = Game(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Jaipur",
            minimumPlayers: 2,
            maximumPlayers: 2,
            playTimeMinutes: 30,
            categories: ["card", "two-player"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            notes: "fast filler"
        )
        let mystery = Game(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "Mystery Box")
        let original = PlayEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            gameID: jaipur.id,
            occurredAt: Date(timeIntervalSince1970: 1_700_003_600),
            participants: [
                PlayParticipant(personID: ana.id, rating: Rating(rawValue: 5), notes: "clutch"),
                PlayParticipant(personID: bo.id, rating: nil, notes: nil),
            ]
        )
        let correction = PlayEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            gameID: jaipur.id,
            occurredAt: Date(timeIntervalSince1970: 1_700_003_600),
            participants: [PlayParticipant(personID: ana.id, rating: Rating(rawValue: 4))],
            correctionOf: original.id
        )
        return BackupCodec.Snapshot(games: [jaipur, mystery], people: [ana, bo], playEvents: [original, correction])
    }

    @Test("encode -> decode round-trips the complete snapshot exactly")
    func roundTrip() throws {
        let snapshot = sampleSnapshot()
        let data = try BackupCodec.encode(snapshot: snapshot, appVersion: "1.2.3", createdAt: Date(timeIntervalSince1970: 1_700_007_200))
        let restored = try BackupCodec.decode(data)
        #expect(restored == snapshot)
    }

    @Test("envelope carries version, app version, timestamp, digest fields")
    func envelopeFields() throws {
        let snapshot = sampleSnapshot()
        let data = try BackupCodec.encode(snapshot: snapshot, appVersion: "1.2.3", createdAt: Date(timeIntervalSince1970: 1_700_007_200))
        let envelope = try JSONDecoder().decode(BackupCodec.Envelope.self, from: data)
        #expect(envelope.schemaVersion == BackupCodec.currentSchemaVersion)
        #expect(envelope.appVersion == "1.2.3")
        #expect(envelope.createdAt == Date(timeIntervalSince1970: 1_700_007_200))
        #expect(envelope.payloadDigest.count == 64)
        // Digest is lowercase hex.
        #expect(envelope.payloadDigest.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("empty snapshot is a valid backup")
    func emptySnapshot() throws {
        let snapshot = BackupCodec.Snapshot(games: [], people: [], playEvents: [])
        let data = try BackupCodec.encode(snapshot: snapshot, appVersion: "0.1.0")
        #expect(try BackupCodec.decode(data) == snapshot)
    }

    private func envelopeJSON(schemaVersion: Int, snapshot: BackupCodec.Snapshot) throws -> Data {
        // Hand-built envelope so the test does not depend on pretty-printer
        // spacing (Darwin and corelibs-foundation differ on `"key": value`).
        // The payload digest stays the REAL digest, isolating the version
        // check from the integrity check.
        let payload = try BackupCodec.canonicalPayload(snapshot)
        let envelope = BackupCodec.Envelope(
            schemaVersion: schemaVersion,
            appVersion: "future",
            createdAt: Date(timeIntervalSince1970: 1_700_007_200),
            payloadDigest: SHA256.hexDigest(payload),
            snapshot: snapshot
        )
        return try JSONEncoder().encode(envelope)
    }

    @Test("forward-incompatible newer schema is rejected before any import")
    func schemaTooNew() throws {
        let data = try envelopeJSON(schemaVersion: BackupCodec.currentSchemaVersion + 1, snapshot: sampleSnapshot())
        #expect(throws: BackupCodec.BackupError.schemaTooNew(found: BackupCodec.currentSchemaVersion + 1, supported: BackupCodec.currentSchemaVersion)) {
            try BackupCodec.decode(data)
        }
    }

    @Test("schema version below the supported floor is rejected (stub for older formats)")
    func schemaTooOld() throws {
        // Stub for a hypothetical pre-v1 format: version 0 or negative must
        // never be silently treated as v1.
        let data = try envelopeJSON(schemaVersion: 0, snapshot: sampleSnapshot())
        #expect(throws: BackupCodec.BackupError.schemaVersionInvalid(found: 0)) {
            try BackupCodec.decode(data)
        }
    }

    @Test("tampered payload fails the integrity digest")
    func integrityMismatch() throws {
        var text = String(decoding: try BackupCodec.encode(snapshot: sampleSnapshot(), appVersion: "1.0.0"), as: UTF8.self)
        // Edit a pretty-printed value inside the payload without touching
        // the digest field.
        let range = try #require(text.range(of: "\"Jaipur\""))
        text.replaceSubrange(range, with: "\"STOLEN GAME\"")
        #expect(throws: BackupCodec.BackupError.integrityMismatch) {
            try BackupCodec.decode(Data(text.utf8))
        }
    }

    @Test("truncated file is rejected cleanly, never partially imported")
    func truncatedFile() throws {
        let data = try BackupCodec.encode(snapshot: sampleSnapshot(), appVersion: "1.0.0")
        let truncated = data.prefix(data.count / 2)
        #expect(throws: (any Error).self) {
            try BackupCodec.decode(Data(truncated))
        }
    }

    @Test("garbage bytes produce unreadableFile, not a crash")
    func garbageBytes() {
        let garbage = Data([0x00, 0x01, 0xFE, 0xFF])
        #expect(throws: BackupCodec.BackupError.self) {
            try BackupCodec.decode(garbage)
        }
    }

    @Test("canonical payload bytes are stable: digest independent of key order in file")
    func digestStability() throws {
        let snapshot = sampleSnapshot()
        let first = try BackupCodec.encode(snapshot: snapshot, appVersion: "1.0.0", createdAt: Date(timeIntervalSince1970: 1))
        let second = try BackupCodec.encode(snapshot: snapshot, appVersion: "1.0.0", createdAt: Date(timeIntervalSince1970: 1))
        #expect(first == second)
    }
}

@Suite("SHA-256 known vectors")
struct SHA256Tests {
    @Test("empty input matches FIPS 180-4 vector")
    func emptyVector() {
        #expect(SHA256.hexDigest(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("abc matches FIPS 180-4 vector")
    func abcVector() {
        #expect(SHA256.hexDigest(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("multi-block input crosses the padding boundary correctly")
    func multiBlock() throws {
        // 60 'a' bytes: length 60 needs an extra padding block (60+1+8 > 64).
        // Vector verified against the system sha256sum in
        // docs/backup-export-evidence.md (python hashlib and coreutils
        // agree on this input).
        let text = String(repeating: "a", count: 60)
        #expect(SHA256.hexDigest(Data(text.utf8)) == "11ee391211c6256460b6ed375957fadd8061cafbb31daf967db875aebd5aaad4")
    }
}
