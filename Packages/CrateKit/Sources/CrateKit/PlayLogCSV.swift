import Foundation

/// RFC 4180 export of the play ledger (issue #7).
///
/// Pure function over the ledger so escaping and unknown-date behavior are
/// fully testable on Linux CI. Every field containing a comma, quote, or
/// line break is quoted with doubled quotes; unicode passes through as-is.
/// Dates render as `yyyy-MM-dd` in UTC or stay empty — an unknown date
/// exports as unknown, never as a guessed day.
public enum PlayLogCSV {
    public static let header = "game,date,players,ratings"

    /// One row per event, in caller order (the app passes
    /// `PlayLedger.effectiveEvents`, so superseded originals never export).
    public static func export(games: [Game], people: [Person], events: [PlayEvent]) -> String {
        let titles = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0.title) })
        let names = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0.name) })

        var lines = [header]
        for event in events {
            let game = titles[event.gameID] ?? "Unknown game"
            let date = event.occurredAt.map(formatDay) ?? ""
            let players = event.participants
                .map { names[$0.personID] ?? "Unknown player" }
                .joined(separator: "; ")
            let ratings = event.participants
                .compactMap { participant -> String? in
                    guard let rating = participant.rating else { return nil }
                    let name = names[participant.personID] ?? "Unknown player"
                    return "\(name): \(rating.rawValue)"
                }
                .joined(separator: "; ")
            lines.append([game, date, players, ratings].map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 4180 field escaping.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "\"" || $0 == "," || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Locale-proof fixed calendar day in UTC (no user locale leaking into
    /// an export file).
    static func formatDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
