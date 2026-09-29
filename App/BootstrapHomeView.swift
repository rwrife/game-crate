import CrateKit
import CrateStore
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class GameCrateModel {
    private let store: CrateStore
    private let gameRepository: any GameRepository
    private let personRepository: any PersonRepository
    private let playRepository: any PlayLedgerRepository

    private let builtInCategoryTags = [
        "abstract", "cooperative", "engine-builder", "family", "party", "strategy", "two-player",
    ]

    private(set) var games: [Game] = []
    private(set) var people: [Person] = []
    private(set) var ledger = PlayLedger()
    private(set) var playCountsByGame: [UUID: Int] = [:]
    var tonightPlayerCount = 2
    var tonightTimeBudgetMinutes = 60
    var errorMessage: String?

    private init(store: CrateStore, startupError: String? = nil) {
        self.store = store
        gameRepository = GRDBGameRepository(db: store.db)
        personRepository = GRDBPersonRepository(db: store.db)
        playRepository = GRDBPlayLedgerRepository(db: store.db)
        errorMessage = startupError
        reload()
    }

    static func make() -> GameCrateModel {
        let args = ProcessInfo.processInfo.arguments

        if args.contains("-ui-testing") {
            let model = GameCrateModel(store: (try? CrateStore.inMemory()) ?? (try! CrateStore.inMemory()))
            if args.contains("-ui-testing-seed-play") {
                model.seedFixtureForDeletionFlow()
            }
            if args.contains("-ui-testing-seed-shortlist") {
                model.seedFixtureForTonightFlow()
            }
            return model
        }

        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("GameCrate", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            return GameCrateModel(store: try CrateStore.atPath(support.appendingPathComponent("gamecrate.sqlite").path))
        } catch {
            return GameCrateModel(
                store: (try? CrateStore.inMemory()) ?? (try! CrateStore.inMemory()),
                startupError: "Game Crate could not open local storage. Running in temporary local mode: \(error.localizedDescription)"
            )
        }
    }

    func reload() {
        do {
            let loadedGames = try gameRepository.allGames()
            let loadedPeople = try personRepository.allPeople()

            var counts: [UUID: Int] = [:]
            var ledgerEvents: [PlayEvent] = []
            for game in loadedGames {
                let gameEvents = try playRepository.events(for: game.id)
                counts[game.id] = gameEvents.count
                ledgerEvents.append(contentsOf: gameEvents)
            }

            games = loadedGames
            people = loadedPeople
            ledger = PlayLedger(events: ledgerEvents)
            playCountsByGame = counts
        } catch {
            errorMessage = "Game Crate could not read local data: \(error.localizedDescription)"
        }
    }

    var tagVocabulary: [String] {
        let userTags = games.flatMap { $0.categories.map(\.rawValue) }
        return Set(builtInCategoryTags + userTags)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func game(id: UUID) -> Game? {
        games.first { $0.id == id }
    }

    func person(id: UUID) -> Person? {
        people.first { $0.id == id }
    }

    func playCount(for gameID: UUID) -> Int {
        playCountsByGame[gameID, default: 0]
    }

    func plays(for gameID: UUID) -> [PlayEvent] {
        do {
            return try playRepository.events(for: gameID)
        } catch {
            errorMessage = "Play events could not be loaded: \(error.localizedDescription)"
            return []
        }
    }

    func effectivePlays(for gameID: UUID) -> [PlayEvent] {
        ledger.effectiveEvents.filter { $0.gameID == gameID }
    }

    func daysSinceLastPlay(for game: Game, asOf: Date = .now, calendar: Calendar = .current) -> Int? {
        let gamePlays = effectivePlays(for: game.id)
        return Derivations.daysSinceLastPlay(plays: gamePlays, asOf: asOf, calendar: calendar)
    }

    func evaluateTonightFit(asOf: Date = .now, calendar: Calendar = .current) -> FitResult {
        let query = FitQuery(
            playerCount: tonightPlayerCount,
            timeBudgetMinutes: tonightTimeBudgetMinutes
        )
        return FitEngine().evaluate(
            games: games,
            ledger: ledger,
            asOf: asOf,
            query: query,
            calendar: calendar
        )
    }

    @discardableResult
    func recordPlay(
        gameID: UUID,
        occurredAt: Date?,
        participantIDs: [UUID],
        ratings: [UUID: Rating] = [:],
        notes: String? = nil,
        correctionOf: UUID? = nil
    ) -> Bool {
        let participants = participantIDs.map { personID in
            PlayParticipant(personID: personID, rating: ratings[personID], notes: nil)
        }
        let event = PlayEvent(
            gameID: gameID,
            occurredAt: occurredAt,
            participants: participants,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines),
            correctionOf: correctionOf
        )
        do {
            try playRepository.append(event)
            reload()
            return true
        } catch {
            errorMessage = "Play could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func upsertGame(_ game: Game) -> Bool {
        do {
            try gameRepository.save(game)
            reload()
            return true
        } catch {
            errorMessage = "Game could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func deleteGame(id: UUID) -> Int? {
        do {
            let citations = try playRepository.events(for: id).count
            try gameRepository.deleteGame(id: id)
            reload()
            return citations
        } catch {
            errorMessage = "Game could not be deleted: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func upsertPerson(_ person: Person) -> Bool {
        do {
            try personRepository.save(person)
            reload()
            return true
        } catch {
            errorMessage = "Person could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func deletePerson(id: UUID) -> Bool {
        do {
            try personRepository.deletePerson(id: id)
            reload()
            return true
        } catch {
            errorMessage = "Person could not be deleted: \(error.localizedDescription)"
            return false
        }
    }

    private func seedFixtureForTonightFlow() {
        guard games.isEmpty else { return }
        do {
            let fittedGame = Game(
                title: "Cascadia",
                minimumPlayers: 1,
                maximumPlayers: 4,
                playTimeMinutes: 45,
                categories: ["family", "strategy"]
            )
            let excludedGame = Game(
                title: "Twilight Imperium",
                minimumPlayers: 3,
                maximumPlayers: 8,
                playTimeMinutes: 360,
                categories: ["strategy"]
            )
            let unspecifiedGame = Game(
                title: "Mystery Box",
                categories: ["party"]
            )
            let person = Person(name: "Ana")
            try gameRepository.save(fittedGame)
            try gameRepository.save(excludedGame)
            try gameRepository.save(unspecifiedGame)
            try personRepository.save(person)
            reload()
        } catch {
            errorMessage = "Fixture seed failed: \(error.localizedDescription)"
        }
    }

    private func seedFixtureForDeletionFlow() {
        guard games.isEmpty else { return }
        do {
            let game = Game(
                title: "Seeded Game",
                minimumPlayers: 2,
                maximumPlayers: 4,
                playTimeMinutes: 45,
                categories: ["family"]
            )
            let person = Person(name: "Seeded Person")
            try gameRepository.save(game)
            try personRepository.save(person)
            try playRepository.append(
                PlayEvent(
                    gameID: game.id,
                    occurredAt: .now,
                    participants: [PlayParticipant(personID: person.id, rating: Rating(rawValue: 4))],
                    notes: "Seed play"
                )
            )
            reload()
        } catch {
            errorMessage = "Fixture seed failed: \(error.localizedDescription)"
        }
    }
}

enum GameCrateTab: Hashable {
    case shelf
    case tonight
    case wall
    case people
}

/// The single iPhone workspace layout seam. Today it deliberately renders a
/// compact single-column stack. If Apple ships fold-region APIs, this is the
/// only type that should map folded quick-log to one display and unfolded
/// wall + workbench to a two-display span. See README "iPhone Duo".
private struct CrateWorkspaceLayout<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
    }
}

struct BootstrapHomeView: View {
    @Bindable var model: GameCrateModel
    @State private var selectedTab: GameCrateTab = .shelf

    var body: some View {
        CrateWorkspaceLayout {
            TabView(selection: $selectedTab) {
                ShelfView(model: model)
                    .tabItem {
                        Label("Shelf", systemImage: "shippingbox")
                            .accessibilityIdentifier("tab.shelf")
                            .accessibilityLabel("Shelf")
                    }
                    .tag(GameCrateTab.shelf)

                TonightView(model: model) {
                    selectedTab = .wall
                }
                .tabItem {
                    Label("Tonight", systemImage: "sparkles")
                        .accessibilityIdentifier("tab.tonight")
                        .accessibilityLabel("Tonight")
                }
                .tag(GameCrateTab.tonight)

                CrateWallView(model: model)
                    .tabItem {
                        Label("Wall", systemImage: "square.grid.2x2")
                            .accessibilityIdentifier("tab.wall")
                            .accessibilityLabel("Wall")
                    }
                    .tag(GameCrateTab.wall)

                PeopleRosterView(model: model)
                    .tabItem {
                        Label("People", systemImage: "person.2")
                            .accessibilityIdentifier("tab.people")
                            .accessibilityLabel("People")
                    }
                    .tag(GameCrateTab.people)
            }
        }
    }
}

private struct TonightView: View {
    @Bindable var model: GameCrateModel
    let onPlaySaved: () -> Void

    @State private var quickLogGame: Game?
    @State private var showingUnspecified = false

    private var result: FitResult { model.evaluateTonightFit() }

    var body: some View {
        NavigationStack {
            List {
                Section("Tonight's fit") {
                    Stepper("Players: \(model.tonightPlayerCount)", value: $model.tonightPlayerCount, in: 1 ... 20)
                        .accessibilityIdentifier("tonight.players")
                        .accessibilityLabel("Tonight player count")
                    Stepper("Time: \(model.tonightTimeBudgetMinutes) minutes", value: $model.tonightTimeBudgetMinutes, in: 15 ... 480, step: 15)
                        .accessibilityIdentifier("tonight.minutes")
                        .accessibilityLabel("Tonight time budget")
                }

                Section("Ranked picks") {
                    if result.shortlist.isEmpty {
                        Text("No known-fit games for these settings.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("shortlist.empty")
                    } else {
                        ForEach(result.shortlist, id: \.game.id) { entry in
                            Button {
                                quickLogGame = entry.game
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.game.title)
                                        .font(.headline)
                                    Text(recencyText(entry.daysSinceLastPlay))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityIdentifier("shortlist.pick.\(entry.game.title)")
                            .accessibilityLabel("Pick \(entry.game.title), \(recencyText(entry.daysSinceLastPlay))")
                        }
                    }
                }

                Section("Needs details") {
                    Button("Unspecified games: \(result.unspecifiedCount)") {
                        showingUnspecified = true
                    }
                    .accessibilityIdentifier("shortlist.unspecified")
                    .accessibilityLabel("Show \(result.unspecifiedCount) games with unspecified fit fields")
                    .disabled(result.unspecifiedGames.isEmpty)
                }

                Section("Excluded") {
                    if result.exclusions.isEmpty {
                        Text("No named exclusions.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(result.exclusions, id: \.game.id) { exclusion in
                            ExclusionDisclosure(exclusion: exclusion)
                        }
                    }
                }
            }
            .navigationTitle("Tonight")
            .sheet(isPresented: $showingUnspecified) {
                NavigationStack {
                    List(result.unspecifiedGames) { game in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.title).font(.headline)
                            Text("Player range or play time is unknown.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("unspecified.game.\(game.title)")
                    }
                    .navigationTitle("Unspecified")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingUnspecified = false }
                                .accessibilityIdentifier("unspecified.done")
                                .accessibilityLabel("Close unspecified games")
                        }
                    }
                }
            }
            .sheet(item: $quickLogGame) { game in
                QuickLogView(model: model, game: game) { saved in
                    quickLogGame = nil
                    if saved { onPlaySaved() }
                }
            }
        }
    }

    private func recencyText(_ days: Int?) -> String {
        guard let days else { return "Never played or date unknown" }
        if days == 0 { return "Played today" }
        if days == 1 { return "Last played 1 day ago" }
        return "Last played \(days) days ago"
    }
}

private struct ExclusionDisclosure: View {
    let exclusion: FitExclusion
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(Array(exclusion.reasons.enumerated()), id: \.offset) { _, reason in
                Text(exclusionText(reason))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(exclusion.game.title)
        }
        .accessibilityIdentifier("shortlist.exclusion.\(exclusion.game.title)")
        .accessibilityLabel("Exclusion reasons for \(exclusion.game.title)")
    }

    private func exclusionText(_ reason: ExclusionReason) -> String {
        switch reason {
        case let .tooFewPlayers(minimum, requested):
            "Needs at least \(minimum) players; tonight has \(requested)."
        case let .tooManyPlayers(maximum, requested):
            "Supports at most \(maximum) players; tonight has \(requested)."
        case let .exceedsTimeBudget(gameMinutes, budgetMinutes):
            "Takes \(gameMinutes) minutes; budget is \(budgetMinutes)."
        case let .missingCategory(categories):
            "Missing categories: \(categories.map(\.rawValue).joined(separator: ", "))."
        }
    }
}

private struct CrateWallView: View {
    @Bindable var model: GameCrateModel
    @State private var historyGame: Game?

    private var fit: FitResult { model.evaluateTonightFit() }

    var body: some View {
        NavigationStack {
            List {
                if model.games.isEmpty {
                    ContentUnavailableView(
                        "The wall is empty",
                        systemImage: "square.grid.2x2",
                        description: Text("Add a game on the Shelf first.")
                    )
                    .accessibilityIdentifier("wall.empty")
                } else {
                    ForEach(model.games) { game in
                        Button {
                            historyGame = game
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(game.title).font(.headline)
                                Text(fitStatus(game))
                                    .font(.subheadline)
                                    .foregroundStyle(fit.shortlist.contains { $0.game.id == game.id } ? Color.green : Color.secondary)
                                Text(lastPlayedText(game))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityIdentifier("wall.game.\(game.title)")
                        .accessibilityLabel("\(game.title), \(fitStatus(game)), \(lastPlayedText(game))")
                    }
                }
            }
            .navigationTitle("Crate Wall")
            .sheet(item: $historyGame) { game in
                GamePlayHistoryView(model: model, game: game) {
                    historyGame = nil
                }
            }
        }
    }

    private func fitStatus(_ game: Game) -> String {
        if fit.shortlist.contains(where: { $0.game.id == game.id }) { return "Fits tonight" }
        if fit.unspecifiedGames.contains(where: { $0.id == game.id }) { return "Fit unknown" }
        return "Does not fit tonight"
    }

    private func lastPlayedText(_ game: Game) -> String {
        let plays = model.effectivePlays(for: game.id)
        guard !plays.isEmpty else { return "Never played" }
        guard let days = model.daysSinceLastPlay(for: game) else { return "Last played: date unknown" }
        if days == 0 { return "Last played today" }
        if days == 1 { return "Last played 1 day ago" }
        return "Last played \(days) days ago"
    }
}

private struct QuickLogView: View {
    @Bindable var model: GameCrateModel
    let game: Game
    let correction: PlayEvent?
    /// Called with `true` after a successful save, `false` on cancel. The
    /// presenting sheet owns dismissal so its `item` state stays in sync.
    let onFinish: (_ saved: Bool) -> Void

    @State private var occurredAt: Date
    @State private var selectedPeople: Set<UUID>
    @State private var ratings: [UUID: Int]
    @State private var notes: String

    init(model: GameCrateModel, game: Game, correction: PlayEvent? = nil, onFinish: @escaping (_ saved: Bool) -> Void) {
        self.model = model
        self.game = game
        self.correction = correction
        self.onFinish = onFinish
        _occurredAt = State(initialValue: correction?.occurredAt ?? .now)
        _selectedPeople = State(initialValue: Set(correction?.participants.map(\.personID) ?? []))
        _ratings = State(initialValue: Dictionary(uniqueKeysWithValues: correction?.participants.compactMap { participant in
            participant.rating.map { (participant.personID, $0.rawValue) }
        } ?? []))
        _notes = State(initialValue: correction?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Play") {
                    LabeledContent("Game", value: game.title)
                    DatePicker("Date", selection: $occurredAt, displayedComponents: [.date])
                        .accessibilityIdentifier("quicklog.date")
                        .accessibilityLabel("Play date")
                }

                Section("Players") {
                    if model.people.isEmpty {
                        Text("No people yet. Save the play now and add participants later with a correction.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.people) { person in
                            Toggle(person.name, isOn: participantBinding(person.id))
                                .accessibilityIdentifier("quicklog.person.\(person.name)")
                                .accessibilityLabel("Include \(person.name)")

                            if selectedPeople.contains(person.id) {
                                Toggle("Rate \(person.name)", isOn: ratingEnabledBinding(person.id))
                                    .accessibilityIdentifier("quicklog.rate.\(person.name)")
                                    .accessibilityLabel("Add rating for \(person.name)")
                                if ratings[person.id] != nil {
                                    Stepper("\(person.name) rating: \(ratings[person.id] ?? 3)", value: ratingBinding(person.id), in: 1 ... 5)
                                        .accessibilityIdentifier("quicklog.rating.\(person.name)")
                                        .accessibilityLabel("Rating for \(person.name)")
                                }
                            }
                        }
                    }
                }

                Section("Optional notes") {
                    TextField("Add later if you want", text: $notes, axis: .vertical)
                        .lineLimit(2 ... 5)
                        .accessibilityIdentifier("quicklog.notes")
                        .accessibilityLabel("Play notes")
                }
            }
            .navigationTitle(correction == nil ? "Quick Log" : "Correct Play")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish(false) }
                        .accessibilityIdentifier("quicklog.cancel")
                        .accessibilityLabel("Cancel play log")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("quicklog.save")
                        .accessibilityLabel("Save play")
                }
            }
        }
    }

    private func participantBinding(_ personID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedPeople.contains(personID) },
            set: { selected in
                if selected { selectedPeople.insert(personID) }
                else {
                    selectedPeople.remove(personID)
                    ratings.removeValue(forKey: personID)
                }
            }
        )
    }

    private func ratingEnabledBinding(_ personID: UUID) -> Binding<Bool> {
        Binding(
            get: { ratings[personID] != nil },
            set: { enabled in
                if enabled { ratings[personID] = ratings[personID] ?? 3 }
                else { ratings.removeValue(forKey: personID) }
            }
        )
    }

    private func ratingBinding(_ personID: UUID) -> Binding<Int> {
        Binding(
            get: { ratings[personID] ?? 3 },
            set: { ratings[personID] = $0 }
        )
    }

    private func save() {
        let domainRatings = ratings.reduce(into: [UUID: Rating]()) { partial, pair in
            partial[pair.key] = Rating(rawValue: pair.value)
        }
        guard model.recordPlay(
            gameID: game.id,
            occurredAt: occurredAt,
            participantIDs: Array(selectedPeople),
            ratings: domainRatings,
            notes: notes,
            correctionOf: correction?.id
        ) else { return }
        onFinish(true)
    }
}

private struct GamePlayHistoryView: View {
    @Bindable var model: GameCrateModel
    let game: Game
    let onDone: () -> Void

    @State private var correction: PlayEvent?

    private var events: [PlayEvent] { model.plays(for: game.id) }
    private var effectiveIDs: Set<UUID> { Set(model.effectivePlays(for: game.id).map(\.id)) }

    var body: some View {
        NavigationStack {
            List {
                if events.isEmpty {
                    Text("No plays logged.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("history.empty")
                } else {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(historyTitle(event)).font(.headline)
                            Text("Players: \(event.participants.count)")
                            if let notes = event.notes, !notes.isEmpty { Text(notes) }
                            if effectiveIDs.contains(event.id) {
                                Button("Correct this play") { correction = event }
                                    .accessibilityIdentifier("history.correct.\(event.id.uuidString)")
                                    .accessibilityLabel("Correct play for \(game.title)")
                            } else {
                                Text("Superseded by a compensating correction")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("history.event.\(event.id.uuidString)")
                    }
                }
            }
            .navigationTitle("\(game.title) History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .accessibilityIdentifier("history.done")
                        .accessibilityLabel("Close play history")
                }
            }
            .sheet(item: $correction) { event in
                QuickLogView(model: model, game: game, correction: event) { _ in
                    correction = nil
                }
            }
        }
    }

    private func historyTitle(_ event: PlayEvent) -> String {
        let prefix = event.correctionOf == nil ? "Play" : "Correction"
        guard let date = event.occurredAt else { return "\(prefix) — date unknown" }
        return "\(prefix) — \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

private enum GameEditorContext: Identifiable, Equatable {
    case create
    case edit(UUID)

    var id: UUID {
        switch self {
        case .create:
            UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        case let .edit(gameID):
            gameID
        }
    }
}

private struct ShelfView: View {
    @Bindable var model: GameCrateModel
    @State private var editorContext: GameEditorContext?

    var body: some View {
        NavigationStack {
            List {
                if model.games.isEmpty {
                    ContentUnavailableView(
                        "No games yet",
                        systemImage: "shippingbox",
                        description: Text("Add your first game to build tonight's shortlist.")
                    )
                    .accessibilityIdentifier("shelf.empty")
                } else {
                    ForEach(model.games) { game in
                        NavigationLink {
                            GameDetailView(model: model, gameID: game.id)
                        } label: {
                            GameRowView(game: game)
                        }
                        .accessibilityIdentifier("game.card.\(game.title)")
                        .accessibilityLabel(gameRowVoiceOverLabel(for: game))
                    }
                }
            }
            .navigationTitle("Shelf")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorContext = .create
                    } label: {
                        Label("Add game", systemImage: "plus")
                    }
                    .accessibilityIdentifier("shelf.addGame")
                    .accessibilityLabel("Add game")
                }
            }
            .sheet(item: $editorContext) { context in
                GameEditorView(
                    model: model,
                    context: context,
                    onSaved: { editorContext = nil },
                    onCancelled: { editorContext = nil }
                )
            }
            .alert(
                "Storage error",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private func gameRowVoiceOverLabel(for game: Game) -> String {
        let categories = game.categories.isEmpty
            ? "No categories"
            : game.categories.map(\.rawValue).joined(separator: ", ")
        return [game.title, playersSummary(for: game), timeSummary(for: game), categories]
            .joined(separator: ", ")
    }

    private func playersSummary(for game: Game) -> String {
        switch (game.minimumPlayers, game.maximumPlayers) {
        case let (minimum?, maximum?):
            return minimum == maximum ? "\(minimum) players" : "\(minimum)-\(maximum) players"
        default:
            return "Players unknown"
        }
    }

    private func timeSummary(for game: Game) -> String {
        if let minutes = game.playTimeMinutes {
            return "\(minutes) minutes"
        }
        return "Time unknown"
    }
}

private struct GameRowView: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(game.title)
                .font(.headline)

            Text(playersSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(timeSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if game.categories.isEmpty {
                Text("No categories")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(game.categories.map(\.rawValue).joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var playersSummary: String {
        switch (game.minimumPlayers, game.maximumPlayers) {
        case let (minimum?, maximum?):
            return minimum == maximum ? "\(minimum) players" : "\(minimum)-\(maximum) players"
        default:
            return "Players unknown"
        }
    }

    private var timeSummary: String {
        if let minutes = game.playTimeMinutes {
            return "\(minutes) minutes"
        }
        return "Time unknown"
    }
}

private struct GameDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var model: GameCrateModel
    let gameID: UUID

    @State private var editorContext: GameEditorContext?
    @State private var pendingDeletePlayCount = 0
    @State private var showingDeleteConfirmation = false

    var body: some View {
        if let game = model.game(id: gameID) {
            List {
                Section("Game") {
                    LabeledContent("Title", value: game.title)
                    LabeledContent("Players", value: playersSummary(for: game))
                    LabeledContent("Play time", value: timeSummary(for: game))
                    LabeledContent("Categories", value: categoriesSummary(for: game))
                    LabeledContent("Notes", value: game.notes?.isEmpty == false ? game.notes! : "—")
                }

                Section("Linked ledger citations") {
                    Text("Deleting this game will cascade-delete \(model.playCount(for: game.id)) play citation(s).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Edit game") {
                        editorContext = .edit(game.id)
                    }
                    .accessibilityIdentifier("game.edit")
                    .accessibilityLabel("Edit game")

                    Button("Delete game", role: .destructive) {
                        pendingDeletePlayCount = model.playCount(for: game.id)
                        showingDeleteConfirmation = true
                    }
                    .accessibilityIdentifier("game.delete")
                    .accessibilityLabel("Delete game")
                }
            }
            .navigationTitle(game.title)
            .sheet(item: $editorContext) { context in
                GameEditorView(
                    model: model,
                    context: context,
                    onSaved: { editorContext = nil },
                    onCancelled: { editorContext = nil }
                )
            }
            .confirmationDialog(
                "Delete this game?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(deleteConfirmationTitle(playCount: pendingDeletePlayCount), role: .destructive) {
                    guard model.deleteGame(id: gameID) != nil else { return }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the game and all linked play rows by SQLite cascade.")
            }
        } else {
            Text("Game not found")
                .foregroundStyle(.secondary)
        }
    }

    private func deleteConfirmationTitle(playCount: Int) -> String {
        let noun = playCount == 1 ? "Play" : "Plays"
        return "Delete Game and \(playCount) \(noun)"
    }

    private func playersSummary(for game: Game) -> String {
        switch (game.minimumPlayers, game.maximumPlayers) {
        case let (minimum?, maximum?):
            return minimum == maximum ? "\(minimum) players" : "\(minimum)-\(maximum) players"
        default:
            return "unknown"
        }
    }

    private func timeSummary(for game: Game) -> String {
        if let minutes = game.playTimeMinutes {
            return "\(minutes) min"
        }
        return "unknown"
    }

    private func categoriesSummary(for game: Game) -> String {
        if game.categories.isEmpty {
            return "none"
        }
        return game.categories.map(\.rawValue).joined(separator: ", ")
    }
}

private struct GameEditorView: View {
    @Bindable var model: GameCrateModel
    let context: GameEditorContext
    let onSaved: () -> Void
    let onCancelled: () -> Void

    @State private var title: String
    @State private var hasPlayerRange: Bool
    @State private var minimumPlayers: Int
    @State private var maximumPlayers: Int
    @State private var hasPlayTime: Bool
    @State private var playTimeMinutes: Int
    @State private var categoriesText: String
    @State private var notes: String
    @State private var validationMessage: String?

    init(model: GameCrateModel, context: GameEditorContext, onSaved: @escaping () -> Void, onCancelled: @escaping () -> Void) {
        self.model = model
        self.context = context
        self.onSaved = onSaved
        self.onCancelled = onCancelled

        let game: Game? = switch context {
        case .create:
            nil
        case let .edit(id):
            model.game(id: id)
        }

        _title = State(initialValue: game?.title ?? "")
        _hasPlayerRange = State(initialValue: game?.minimumPlayers != nil && game?.maximumPlayers != nil)
        _minimumPlayers = State(initialValue: max(1, game?.minimumPlayers ?? 2))
        _maximumPlayers = State(initialValue: max(1, game?.maximumPlayers ?? 4))
        _hasPlayTime = State(initialValue: game?.playTimeMinutes != nil)
        _playTimeMinutes = State(initialValue: max(1, game?.playTimeMinutes ?? 45))
        _categoriesText = State(initialValue: game?.categories.map(\.rawValue).joined(separator: ", ") ?? "")
        _notes = State(initialValue: game?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("game.error")
                    }
                }

                Section("Basics") {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("game.title")
                        .accessibilityLabel("Game title")

                    Toggle("Specify player range", isOn: $hasPlayerRange)
                        .accessibilityIdentifier("game.hasPlayerRange")
                        .accessibilityLabel("Specify player range")

                    if hasPlayerRange {
                        Stepper(value: $minimumPlayers, in: 1 ... 20) {
                            Text("Minimum players: \(minimumPlayers)")
                        }
                        .accessibilityIdentifier("game.minPlayers")
                        .accessibilityLabel("Minimum players")

                        Stepper(value: $maximumPlayers, in: 1 ... 20) {
                            Text("Maximum players: \(maximumPlayers)")
                        }
                        .accessibilityIdentifier("game.maxPlayers")
                        .accessibilityLabel("Maximum players")
                    } else {
                        Text("Players unknown")
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Specify play time", isOn: $hasPlayTime)
                        .accessibilityIdentifier("game.hasPlayTime")
                        .accessibilityLabel("Specify play time")

                    if hasPlayTime {
                        Stepper(value: $playTimeMinutes, in: 1 ... 480, step: 5) {
                            Text("Play time minutes: \(playTimeMinutes)")
                        }
                        .accessibilityIdentifier("game.minutes")
                        .accessibilityLabel("Play time minutes")
                    } else {
                        Text("Time unknown")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Categories") {
                    TextField("Comma-separated tags", text: $categoriesText)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("game.categories")
                        .accessibilityLabel("Categories")

                    if !model.tagVocabulary.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(model.tagVocabulary, id: \.self) { tag in
                                    Button(tag) {
                                        appendTag(tag)
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("game.tag.\(tag)")
                                    .accessibilityLabel("Add category \(tag)")
                                }
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2 ... 5)
                        .accessibilityIdentifier("game.notes")
                        .accessibilityLabel("Game notes")
                }
            }
            .navigationTitle(context == .create ? "Add Game" : "Edit Game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancelled)
                        .accessibilityIdentifier("game.cancel")
                        .accessibilityLabel("Cancel game editor")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("game.save")
                        .accessibilityLabel("Save game")
                }
            }
        }
    }

    private func appendTag(_ tag: String) {
        var tags = parsedCategoryStrings
        if !tags.contains(where: { $0.compare(tag, options: .caseInsensitive) == .orderedSame }) {
            tags.append(tag)
            categoriesText = tags.joined(separator: ", ")
        }
    }

    private var parsedCategoryStrings: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for raw in categoriesText.split(separator: ",") {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            let key = token.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(token)
        }
        return ordered
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationMessage = "Title is required."
            return
        }

        if hasPlayerRange, minimumPlayers > maximumPlayers {
            validationMessage = "Minimum players must be less than or equal to maximum players."
            return
        }

        let game = Game(
            id: context.gameID ?? UUID(),
            title: trimmedTitle,
            minimumPlayers: hasPlayerRange ? minimumPlayers : nil,
            maximumPlayers: hasPlayerRange ? maximumPlayers : nil,
            playTimeMinutes: hasPlayTime ? playTimeMinutes : nil,
            categories: parsedCategoryStrings.map { CategoryTag($0) },
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard model.upsertGame(game) else { return }
        validationMessage = nil
        onSaved()
    }
}

private enum PersonEditorContext: Identifiable, Equatable {
    case create
    case edit(UUID)

    var id: UUID {
        switch self {
        case .create:
            UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
        case let .edit(personID):
            personID
        }
    }
}

private struct PeopleRosterView: View {
    @Bindable var model: GameCrateModel
    @State private var editorContext: PersonEditorContext?

    var body: some View {
        NavigationStack {
            List {
                if model.people.isEmpty {
                    ContentUnavailableView(
                        "No people yet",
                        systemImage: "person.2",
                        description: Text("Add people as local names only. Contacts are never requested.")
                    )
                    .accessibilityIdentifier("people.empty")
                } else {
                    ForEach(model.people) { person in
                        Button {
                            editorContext = .edit(person.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.name)
                                    .font(.headline)
                                Text(person.notes?.isEmpty == false ? person.notes! : "Local profile")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityIdentifier("person.row.\(person.name)")
                        .accessibilityLabel("Person \(person.name)")
                    }
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorContext = .create
                    } label: {
                        Label("Add person", systemImage: "plus")
                    }
                    .accessibilityIdentifier("people.addPerson")
                    .accessibilityLabel("Add person")
                }
            }
            .sheet(item: $editorContext) { context in
                PersonEditorView(
                    model: model,
                    context: context,
                    onSaved: { editorContext = nil },
                    onCancelled: { editorContext = nil }
                )
            }
            .alert(
                "Storage error",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}

private struct PersonEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var model: GameCrateModel
    let context: PersonEditorContext
    let onSaved: () -> Void
    let onCancelled: () -> Void

    @State private var name: String
    @State private var notes: String
    @State private var validationMessage: String?
    @State private var showingDeleteConfirmation = false

    init(model: GameCrateModel, context: PersonEditorContext, onSaved: @escaping () -> Void, onCancelled: @escaping () -> Void) {
        self.model = model
        self.context = context
        self.onSaved = onSaved
        self.onCancelled = onCancelled

        let person: Person? = switch context {
        case .create:
            nil
        case let .edit(id):
            model.person(id: id)
        }

        _name = State(initialValue: person?.name ?? "")
        _notes = State(initialValue: person?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("person.error")
                    }
                }

                Section("Person") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("person.name")
                        .accessibilityLabel("Person name")

                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2 ... 5)
                        .accessibilityIdentifier("person.notes")
                        .accessibilityLabel("Person notes")
                }

                if case let .edit(personID) = context {
                    Section {
                        Button("Delete Local Person", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                        .accessibilityIdentifier("person.delete")
                        .accessibilityLabel("Delete person")
                        .confirmationDialog(
                            "Delete this person?",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Delete Person", role: .destructive) {
                                guard model.deletePerson(id: personID) else { return }
                                dismiss()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("People are stored as local names only. This action removes the local profile.")
                        }
                    }
                }
            }
            .navigationTitle(context == .create ? "Add Person" : "Edit Person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancelled)
                        .accessibilityIdentifier("person.cancel")
                        .accessibilityLabel("Cancel person editor")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("person.save")
                        .accessibilityLabel("Save person")
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Name is required."
            return
        }

        let person = Person(
            id: context.personID ?? UUID(),
            name: trimmedName,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard model.upsertPerson(person) else { return }
        validationMessage = nil
        onSaved()
    }
}

private extension GameEditorContext {
    var gameID: UUID? {
        if case let .edit(id) = self {
            return id
        }
        return nil
    }
}

private extension PersonEditorContext {
    var personID: UUID? {
        if case let .edit(id) = self {
            return id
        }
        return nil
    }
}
