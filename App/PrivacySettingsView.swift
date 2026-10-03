import CrateKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// Privacy & portability sheet for issue #7: user-owned backup/restore and
// CSV export, all through the Files app. No cloud, no sync, no transfer
// path — every byte moves only to/from files the user picks. The import
// module above is the OS type-declaration framework used by the document
// pickers; it declares file types and nothing else.

/// Write-only document wrapper: the app hands the pickers exact bytes the
/// model serialized. Reading is done directly from the chosen URL so the
/// decoded backup always passes through `BackupCodec` validation.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Backup/export/restore destination (issue #7). Restore is preview-first:
/// choosing a file decodes + fully validates it and shows a counts diff;
/// nothing touches the store until the user taps "Replace crate", and any
/// rejection keeps the current data untouched.
struct PrivacySettingsSheet: View {
    @Bindable var model: GameCrateModel
    @Environment(\.dismiss) private var dismiss

    @State private var exportDocument: ExportDocument?
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = ""
    @State private var importPresented = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Your data stays on this device") {
                    Text("Backups and exports are files you own, saved wherever you choose in the Files app. Game Crate has no account, no cloud, and no way to send data anywhere.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("privacy.explanation")
                }

                Section("Export") {
                    Button("Export backup (JSON)") {
                        guard let data = model.backupFileData() else { return }
                        exportContentType = .json
                        exportFilename = "gamecrate-backup"
                        exportDocument = ExportDocument(data: data)
                    }
                    .accessibilityIdentifier("privacy.exportBackup")

                    Button("Export play log (CSV)") {
                        guard let data = model.csvExportData() else { return }
                        exportContentType = .commaSeparatedText
                        exportFilename = "gamecrate-playlog"
                        exportDocument = ExportDocument(data: data)
                    }
                    .accessibilityIdentifier("privacy.exportCSV")
                }

                Section("Restore") {
                    Button("Choose a backup file…") {
                        importPresented = true
                    }
                    .accessibilityIdentifier("privacy.restore")

                    if let restoreErrorMessage = model.restoreErrorMessage {
                        Text(restoreErrorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("restore.error")
                    }

                    if let preview = model.pendingRestore {
                        RestorePreviewCard(model: model, preview: preview)
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("privacy.status")
                    }
                }
            }
            .navigationTitle("Backup & export")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("privacy.done")
                }
            }
            .fileExporter(
                isPresented: Binding(
                    get: { exportDocument != nil },
                    set: { if !$0 { exportDocument = nil } }
                ),
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportFilename
            ) { result in
                switch result {
                case .success:
                    statusMessage = "Export finished — the file is yours."
                case .failure(let error):
                    statusMessage = "Export failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $importPresented, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    if let data = Self.readContents(of: url) {
                        model.startRestorePreview(from: data)
                    } else {
                        model.restoreErrorMessage = "Could not read the chosen file."
                    }
                case .failure(let error):
                    model.restoreErrorMessage = "Could not read the chosen file: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Reads a user-picked file with the sandbox's security-scoped access,
    /// always releasing the scope.
    private static func readContents(of url: URL) -> Data? {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}

/// Counts diff + atomic replace decision (issue #7). The numbers on BOTH
/// sides are integer counts only — the preview promises nothing and
/// guesses nothing.
private struct RestorePreviewCard: View {
    @Bindable var model: GameCrateModel
    let preview: GameCrateModel.RestorePreview

    var body: some View {
        // NOTE: no accessibilityIdentifier on this container — an
        // identifier on a multi-element container overwrites the children's
        // identifiers in the AX tree (observed as phantom "found but never
        // hittable" rows in sibling repos). The preview is identified by
        // its title text and its buttons individually.
        VStack(alignment: .leading, spacing: 6) {
            Text("Restore preview")
                .font(.headline)
                .accessibilityIdentifier("restore.preview.title")
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("restore.preview.summary")

            Button("Replace crate") {
                model.confirmRestore()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .accessibilityIdentifier("restore.replace")

            Button("Cancel, keep my data") {
                model.cancelRestore()
            }
            .accessibilityIdentifier("restore.cancel")
        }
    }

    private var summary: String {
        let incoming = PlayLedger(events: preview.snapshot.playEvents).effectiveEvents.count
        return "Backup contains \(games(preview.snapshot.games.count)), \(people(preview.snapshot.people.count)), and \(plays(incoming)). Replacing swaps out your current \(games(preview.currentGameCount)), \(people(preview.currentPersonCount)), and \(plays(preview.currentPlayCount)). This cannot be undone — export a backup first if unsure."
    }

    private func games(_ count: Int) -> String {
        count == 1 ? "1 game" : "\(count) games"
    }

    private func people(_ count: Int) -> String {
        count == 1 ? "1 person" : "\(count) people"
    }

    private func plays(_ count: Int) -> String {
        count == 1 ? "1 play" : "\(count) plays"
    }
}
