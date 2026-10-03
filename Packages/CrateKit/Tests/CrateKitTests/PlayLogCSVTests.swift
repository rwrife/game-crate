import Foundation
import Testing
@testable import CrateKit

@Suite("PlayLogCSV: RFC 4180 escaping and unknown-safe dates")
struct PlayLogCSVTests {
    private func fixture() -> (games: [Game], people: [Person], events: [PlayEvent]) {
        let ana = Person(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!, name: "Ana")
        let josé = Person(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000b")!, name: "José \"Jo\" Ñoño")
        let tricky = Game(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Twister, the \"Movie\" Game\nRound 2",
            minimumPlayers: 2,
            maximumPlayers: 4
        )
        let plain = Game(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "Jaipur")
        let dated = PlayEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            gameID: tricky.id,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000), // 2023-11-14 UTC
            participants: [
                PlayParticipant(personID: ana.id, rating: Rating(rawValue: 4)),
                PlayParticipant(personID: josé.id, rating: nil),
            ]
        )
        let undated = PlayEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            gameID: plain.id,
            occurredAt: nil,
            participants: [PlayParticipant(personID: ana.id, rating: Rating(rawValue: 5))]
        )
        return ([tricky, plain], [ana, josé], [dated, undated])
    }

    @Test("header is stable")
    func header() {
        let f = fixture()
        let csv = PlayLogCSV.export(games: f.games, people: f.people, events: [])
        #expect(csv == "game,date,players,ratings\r\n")
    }

    @Test("fields with commas, quotes, and newlines are RFC 4180 escaped")
    func escaping() {
        let f = fixture()
        let csv = PlayLogCSV.export(games: f.games, people: f.people, events: [f.events[0]])
        // Title contains comma, quotes, newline => quoted with doubled quotes.
        #expect(csv.contains("\"Twister, the \"\"Movie\"\" Game\nRound 2\""))
        // Unicode name with quotes, joined into the players field => the
        // whole field quoted, inner quotes doubled, unicode intact.
        #expect(csv.contains("\"Ana; José \"\"Jo\"\" Ñoño\""))
        // Date rendered as fixed ISO day in UTC.
        #expect(csv.contains("2023-11-14"))
        // Ratings only for participants that have one.
        #expect(csv.contains("Ana: 4"))
        #expect(!csv.contains("Jo\"\": 5"))
    }

    @Test("unknown date exports as empty, never a guessed day")
    func unknownDate() {
        let f = fixture()
        let csv = PlayLogCSV.export(games: f.games, people: f.people, events: [f.events[1]])
        // Jaipur,empty date,Ana,Ana: 5
        let rows = csv.components(separatedBy: "\r\n")
        let jaipur = rows.first(where: { $0.contains("Jaipur") })
        #expect(jaipur == "Jaipur,,Ana,Ana: 5")
    }

    @Test("plain fields are not quoted; CRLF line endings throughout")
    func plainRows() {
        let f = fixture()
        let csv = PlayLogCSV.export(games: f.games, people: f.people, events: [f.events[1]])
        #expect(csv.hasPrefix("game,date,players,ratings\r\nJaipur,,Ana,Ana: 5\r\n"))
    }

    @Test("participant missing from roster renders as Unknown player, never dropped")
    func unknownEntities() {
        let ghost = UUID(uuidString: "00000000-0000-0000-0000-0000000000ff")!
        let event = PlayEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            gameID: UUID(uuidString: "00000000-0000-0000-0000-0000000000ee")!,
            participants: [PlayParticipant(personID: ghost, rating: Rating(rawValue: 2))]
        )
        let csv = PlayLogCSV.export(games: [], people: [], events: [event])
        #expect(csv.contains("Unknown game"))
        #expect(csv.contains("Unknown player"))
        #expect(csv.contains("Unknown player: 2"))
    }

    @Test("day formatting is UTC-fixed and locale-independent")
    func dayFormat() {
        // 23:30 UTC on 2024-02-29 (leap day).
        let date = Date(timeIntervalSince1970: 1_709_249_400)
        #expect(PlayLogCSV.formatDay(date) == "2024-02-29")
    }

    @Test("escaping unit checks")
    func escapeRules() {
        #expect(PlayLogCSV.escape("plain") == "plain")
        #expect(PlayLogCSV.escape("a,b") == "\"a,b\"")
        #expect(PlayLogCSV.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(PlayLogCSV.escape("line1\nline2") == "\"line1\nline2\"")
        #expect(PlayLogCSV.escape("carriage\rreturn") == "\"carriage\rreturn\"")
        #expect(PlayLogCSV.escape("héllo") == "héllo")
    }
}
