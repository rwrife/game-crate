import CrateKit
import Foundation
import SwiftUI

// Insights screens for issue #6: per-player profiles and the shelf-hole list.
//
// Hard contract (issue #6 acceptance):
// - Every number shown here is an integer count straight from the ledger.
//   No personality labels, no predictions, no averages presented as facts,
//   no wellness/psychology framing of any kind.
// - Unknown data renders as unknown. Absent history is zero/empty counts,
//   never interpolated values.
// - The shelf-hole list only answers user-authored requests (the user's own
//   tags/ranges) and each line names its evidence: proven matches and the
//   count of unspecified-field games excluded from the proof.
// - This file must remain free of network and tracking symbols; the CI
//   UI-target hygiene gate enforces that (comment wording here deliberately
//   avoids the gate's own forbidden-token list).

private func pluralPlays(_ count: Int) -> String {
    count == 1 ? "1 play" : "\(count) plays"
}

private func pluralGames(_ count: Int) -> String {
    count == 1 ? "1 game" : "\(count) games"
}

/// Second tab-level destination: count-only profiles + explainable shelf holes.
struct InsightsView: View {
    @Bindable var model: GameCrateModel

    var body: some View {
        NavigationStack {
            List {
                Section("Player profiles") {
                    if model.people.isEmpty {
                        Text("Add people on the People tab to see their play and rating counts.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("insights.profiles.empty")
                    } else {
                        ForEach(model.people) { person in
                            NavigationLink {
                                PlayerProfileView(model: model, personID: person.id)
                            } label: {
                                Text(person.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityIdentifier("insights.person.\(person.name)")
                            .accessibilityLabel("\(person.name), \(pluralPlays(model.profile(for: person.id).playCount))")
                        }
                    }
                }

                Section("Shelf holes") {
                    ShelfHolesSection(model: model)
                }
            }
            .navigationTitle("Insights")
        }
    }
}

// MARK: - Shelf holes

private struct ShelfHolesSection: View {
    @Bindable var model: GameCrateModel

    var body: some View {
        let coverage = model.shelfCoverage()

        if coverage.isEmpty {
            Text("No hole requests yet. Describe a shape below, for example “no 2-player game under 30 minutes”.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("holes.empty")
        } else {
            ForEach(Array(coverage.enumerated()), id: \.offset) { index, result in
                VStack(alignment: .leading, spacing: 5) {
                    Text(holeLabel(result.hole))
                        .font(.headline)
                        .accessibilityIdentifier("holes.row.\(index)")
                    Text(holeExplanation(result))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("holes.explain.\(index)")
                    Button("Remove") {
                        model.removeHoleRequest(at: index)
                    }
                    .accessibilityIdentifier("holes.remove.\(index)")
                    .accessibilityLabel("Remove hole request \(holeLabel(result.hole))")
                }
            }
        }

        Stepper("Min players: \(model.draftMinPlayers)", value: $model.draftMinPlayers, in: 1 ... 20)
            .accessibilityIdentifier("hole.min")
            .accessibilityLabel("Hole minimum players")
        Stepper("Max players: \(model.draftMaxPlayers)", value: $model.draftMaxPlayers, in: 1 ... 20)
            .accessibilityIdentifier("hole.max")
            .accessibilityLabel("Hole maximum players")
        Stepper("Within: \(model.draftMaxMinutes) minutes", value: $model.draftMaxMinutes, in: 15 ... 480, step: 15)
            .accessibilityIdentifier("hole.minutes")
            .accessibilityLabel("Hole maximum minutes")

        Toggle("Limit to a category", isOn: $model.draftUsesCategory)
            .accessibilityIdentifier("hole.category")
            .accessibilityLabel("Limit hole request to a category")

        if model.draftUsesCategory {
            TextField("Category tag", text: $model.draftCategoryTag)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("hole.categoryTag")
                .accessibilityLabel("Hole category tag")

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.tagVocabulary, id: \.self) { tag in
                        Button(tag) {
                            model.draftCategoryTag = tag
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("hole.tag.\(tag)")
                        .accessibilityLabel("Use category \(tag)")
                    }
                }
            }
        }

        if let holeValidationError = model.holeValidationError {
            Text(holeValidationError)
                .foregroundStyle(.red)
                .accessibilityIdentifier("hole.error")
        }

        Button("Add hole request") {
            model.addDraftHoleRequest()
        }
        .accessibilityIdentifier("hole.add")
        .accessibilityLabel("Add hole request")
    }

    private func holeLabel(_ hole: ShelfHole) -> String {
        let range = hole.minPlayers == hole.maxPlayers
            ? "\(hole.minPlayers) players"
            : "\(hole.minPlayers)-\(hole.maxPlayers) players"
        var label = "\(range) within \(hole.maxMinutes) min"
        if let category = hole.category {
            label += " · \(category.rawValue)"
        }
        return label
    }

    private func holeExplanation(_ result: ShelfCoverage) -> String {
        var text: String
        if result.matchingGameCount == 0 {
            text = "Hole: no shelf game provably covers this."
        } else {
            let titles = model.titles(fitting: result.hole).joined(separator: ", ")
            text = "\(result.matchingGameCount) proven match\(result.matchingGameCount == 1 ? "" : "es"): \(titles)"
        }
        if result.unspecifiedGameCount > 0 {
            text += " (\(pluralGames(result.unspecifiedGameCount)) with unspecified fields never counted.)"
        }
        return text
    }
}

// MARK: - Player profile

private struct PlayerProfileView: View {
    @Bindable var model: GameCrateModel
    let personID: UUID

    private var person: Person? { model.person(id: personID) }
    private var profile: PlayerProfileCounts { model.profile(for: personID) }

    var body: some View {
        List {
            Section("Plays") {
                Text("\(pluralPlays(profile.playCount)) logged")
                    .accessibilityIdentifier("profile.plays.\(nameSuffix)")
                if profile.playCount == 0 {
                    Text("No plays logged yet — nothing to count, nothing guessed.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.no-plays.\(nameSuffix)")
                }
            }

            Section("Ratings") {
                Text("\(profile.ratingCount) of \(profile.playCount) plays rated")
                    .accessibilityIdentifier("profile.rated.\(nameSuffix)")
                if profile.ratingCount == 0 {
                    if profile.playCount == 0 {
                        Text("No ratings because there are no plays yet.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("profile.no-ratings-empty.\(nameSuffix)")
                    } else {
                        Text("No ratings recorded yet — the distribution stays zero, nothing is guessed.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("profile.no-ratings-short.\(nameSuffix)")
                    }
                }
                ForEach(1 ... 5, id: \.self) { stars in
                    let count = profile.ratingDistribution[stars] ?? 0
                    Text("\(stars) star\(stars == 1 ? "" : "s"): \(count)")
                        .accessibilityIdentifier("profile.rating.\(stars).\(nameSuffix)")
                }
            }

            Section("Categories") {
                if profile.categoryCounts.isEmpty {
                    Text("No category counts yet — this appears once rated or unrated plays have tagged games.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.no-categories.\(nameSuffix)")
                } else {
                    ForEach(
                        profile.categoryCounts.keys.sorted {
                            $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending
                        },
                        id: \.self
                    ) { category in
                        Text("\(category.rawValue): \(profile.categoryCounts[category] ?? 0)")
                            .accessibilityIdentifier("profile.category.\(category.rawValue).\(nameSuffix)")
                    }
                }
            }
        }
        .navigationTitle(person?.name ?? "Profile")
    }

    /// Person-name suffix keeps identifiers unique across pushed profiles.
    private var nameSuffix: String {
        person?.name ?? personID.uuidString
    }
}
