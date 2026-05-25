// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import GokanCore
import GokanEngine
import GokanModels

public struct GokanRootView: View {
    private let initialSGFText: String?
    private let initialModelCatalogData: Data?
    @State private var model: GokanAppModel
    @State private var didLoadInitialSGFText = false
    @State private var didLoadInitialModelCatalogData = false

    @MainActor
    public init(
        initialSGFText: String? = nil,
        forceMockEngine: Bool = false,
        modelCatalog: GokanModelCatalog = .empty,
        initialModelCatalogData: Data? = nil,
        initialEngineKind: AnalysisEngineKind? = nil,
        initialKataGoModelSettings: KataGoModelSettings? = nil
    ) {
        self.initialSGFText = initialSGFText
        self.initialModelCatalogData = initialModelCatalogData
        let appModel = forceMockEngine
            ? GokanAppModel(engine: MockAnalysisEngine(), modelCatalog: modelCatalog)
            : GokanAppModel(modelCatalog: modelCatalog)
        if let initialEngineKind {
            appModel.engineKind = initialEngineKind
        }
        if let initialKataGoModelSettings {
            appModel.kataGoModelSettings = initialKataGoModelSettings
        }
        _model = State(
            initialValue: appModel
        )
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            BoardWorkspaceView(model: model)
        }
        .task(id: model.analysisRequestVersion) {
            await model.analyze()
        }
        .onOpenURL { url in
            model.loadSGFFile(at: url)
        }
        .onAppear {
            loadInitialModelCatalogDataIfNeeded()
            loadInitialSGFTextIfNeeded()
        }
    }

    private func loadInitialModelCatalogDataIfNeeded() {
        guard didLoadInitialModelCatalogData == false,
              let initialModelCatalogData,
              initialModelCatalogData.isEmpty == false else {
            return
        }

        didLoadInitialModelCatalogData = true
        model.loadModelCatalogData(initialModelCatalogData)
    }

    private func loadInitialSGFTextIfNeeded() {
        guard didLoadInitialSGFText == false,
              let initialSGFText,
              initialSGFText.isEmpty == false else {
            return
        }

        didLoadInitialSGFText = true
        model.loadSGFText(initialSGFText)
    }
}

private struct SidebarView: View {
    @Bindable var model: GokanAppModel
    @State private var isImportingSGF = false
    @State private var isImportingModelCatalog = false
    @State private var isExportingSGF = false
    @State private var exportDocument = SGFFileDocument()

    var body: some View {
        List {
            Section("Game") {
                Label("\(model.game.board.size.width)x\(model.game.board.size.height)", systemImage: "square.grid.3x3")
                    .accessibilityIdentifier("gokan.board-size")
                Label("Move \(model.game.currentMoveIndex) / \(model.game.moves.count)", systemImage: "list.number")
                    .accessibilityIdentifier("gokan.move-count")
                Label("\(model.game.nextPlayer.rawValue.capitalized) to play", systemImage: "circle.lefthalf.filled")
                    .accessibilityIdentifier("gokan.next-player")
            }

            Section("Game Info") {
                TextField("Game name", text: metadataBinding(\.gameName))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("gokan.metadata.game-name")
                TextField("Event", text: metadataBinding(\.event))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("gokan.metadata.event")
                TextField("Date", text: metadataBinding(\.date))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("gokan.metadata.date")
                TextField("Black player", text: metadataBinding(\.blackPlayerName))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("gokan.metadata.black-player")
                TextField("White player", text: metadataBinding(\.whitePlayerName))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("gokan.metadata.white-player")
                TextField("Komi", text: metadataBinding(\.komi))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("gokan.metadata.komi")
                TextField("Result", text: metadataBinding(\.result))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("gokan.metadata.result")
            }

            Section("Controls") {
                Button {
                    model.newGame()
                } label: {
                    Label("New Game", systemImage: "doc.badge.plus")
                }

                Button {
                    model.pass()
                } label: {
                    Label("Pass", systemImage: "arrow.uturn.forward")
                }
                .accessibilityIdentifier("gokan.pass")

                HStack {
                    Button {
                        model.goToFirstMove()
                    } label: {
                        Image(systemName: "backward.end")
                    }
                    .disabled(model.game.canStepBackward == false)
                    .help("First move")

                    Button {
                        model.previousMove()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(model.game.canStepBackward == false)
                    .help("Previous move")

                    Button {
                        model.nextMove()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(model.game.canStepForward == false)
                    .help("Next move")

                    Button {
                        model.goToLastMove()
                    } label: {
                        Image(systemName: "forward.end")
                    }
                    .disabled(model.game.canStepForward == false)
                    .help("Last move")
                }
                .buttonStyle(.borderless)

                Button {
                    do {
                        try model.exportSGFText()
                    } catch {
                        model.documentError = String(describing: error)
                    }
                } label: {
                    Label("Export SGF", systemImage: "square.and.arrow.up")
                }
            }

            if model.game.moveListItems.isEmpty == false {
                Section("Moves") {
                    ForEach(model.game.moveListItems) { item in
                        Button {
                            model.goToMove(item.index)
                        } label: {
                            Label(moveListTitle(for: item), systemImage: item.isCurrent ? "checkmark.circle.fill" : "circle")
                        }
                        .disabled(item.isCurrent)
                    }
                }
            }

            if model.game.variationChoices.count > 1 {
                Section("Variations") {
                    ForEach(model.game.variationChoices) { choice in
                        Button {
                            model.selectVariation(at: choice.index)
                        } label: {
                            Label(variationTitle(for: choice), systemImage: choice.isSelected ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
            }

            Section("Engine") {
                Picker("Engine", selection: $model.engineKind) {
                    ForEach(AnalysisEngineKind.allCases) { kind in
                        Text(kind.displayName)
                            .tag(kind)
                    }
                }
                .accessibilityIdentifier("gokan.engine-picker")

                Stepper(
                    value: $model.analysisVisits,
                    in: GokanAppModel.analysisVisitsRange,
                    step: GokanAppModel.analysisVisitsStep
                ) {
                    Label("\(model.analysisVisits) visits", systemImage: "speedometer")
                }
                .accessibilityIdentifier("gokan.analysis-visits-control")

                if model.engineKind == .kataGo {
                    #if os(macOS)
                    TextField("Executable path", text: $model.kataGoSettings.executablePath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("gokan.katago-executable-path")
                    #endif
                }

                Label(model.engineStatus.message, systemImage: engineStatusSystemImage)
                    .foregroundStyle(engineStatusColor)
                    .accessibilityIdentifier("gokan.engine-status")

                Button {
                    Task {
                        await model.analyze()
                    }
                } label: {
                    Label("Analyze Now", systemImage: "play.circle")
                }
                .accessibilityIdentifier("gokan.analyze-now")
            }

            if model.engineKind == .kataGo {
                Section("KataGo Model") {
                    #if os(macOS)
                    TextField("Manual model path", text: $model.kataGoSettings.modelPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("gokan.katago-manual-model-path")
                    TextField("Manual config path", text: $model.kataGoSettings.configPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("gokan.katago-manual-config-path")
                    #endif

                    Text("Manual model paths override selected model profiles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(modelCatalogStatusTitle, systemImage: "list.bullet.rectangle")
                        .accessibilityIdentifier("gokan.model-catalog-status")
                    Text("Catalogs are metadata only. Provide model and config files separately under the cache root.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        isImportingModelCatalog = true
                    } label: {
                        Label("Load Catalog JSON", systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("gokan.model-catalog-import")

                    Button(role: .destructive) {
                        model.clearModelCatalog()
                    } label: {
                        Label("Clear Catalog", systemImage: "trash")
                    }
                    .disabled(model.modelCatalog.profiles.isEmpty)
                    .accessibilityIdentifier("gokan.model-catalog-clear")

                    if let modelCatalogError = model.modelCatalogError {
                        Label(modelCatalogError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("gokan.model-catalog-error")
                    }

                    Picker("Model profile", selection: $model.kataGoModelSettings.selectedProfileID) {
                        Text("Manual paths / no profile")
                            .tag("")
                        ForEach(model.modelCatalog.profiles) { profile in
                            Text(profile.displayName)
                                .tag(profile.id)
                        }
                        if let unknownProfileID {
                            Text("Unknown profile (\(unknownProfileID))")
                                .tag(unknownProfileID)
                        }
                    }
                    .accessibilityIdentifier("gokan.model-profile-picker")

                    if model.modelCatalog.profiles.isEmpty {
                        Text("No model profiles are loaded. Load a metadata catalog JSON to select profiles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Cache root", text: $model.kataGoModelSettings.cacheRootPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("gokan.model-cache-root")

                    Label(model.kataGoModelStatus.message, systemImage: modelStatusSystemImage)
                        .foregroundStyle(modelStatusColor)
                        .accessibilityIdentifier("gokan.katago-model-status")

                    Button {
                        Task {
                            await model.verifySelectedKataGoModelChecksum()
                        }
                    } label: {
                        Label("Verify Checksum", systemImage: "checkmark.seal")
                    }
                    .disabled(model.canVerifySelectedKataGoModelChecksum == false)
                    .accessibilityIdentifier("gokan.model-verify-checksum")

                    if let selectedProfile = model.selectedKataGoModelProfile {
                        modelProfileDetails(for: selectedProfile)
                    }
                }
            }

            if let diagnostics = model.analysisDiagnostics {
                Section("Diagnostics") {
                    Label(diagnosticsOutcomeTitle(for: diagnostics.outcome), systemImage: diagnosticsOutcomeSystemImage(for: diagnostics.outcome))
                        .foregroundStyle(diagnosticsOutcomeColor(for: diagnostics.outcome))
                        .accessibilityIdentifier("gokan.analysis-diagnostics-status")
                    Label(diagnostics.engineKind.displayName, systemImage: "cpu")
                        .accessibilityIdentifier("gokan.analysis-diagnostics-engine")
                    Label(
                        "\(diagnostics.boardSize.width)x\(diagnostics.boardSize.height), move \(diagnostics.moveIndex) / \(diagnostics.moveCount)",
                        systemImage: "scope"
                    )
                    .accessibilityIdentifier("gokan.analysis-diagnostics-position")
                    Label("\(diagnostics.requestedVisits) requested visits", systemImage: "speedometer")
                        .accessibilityIdentifier("gokan.analysis-diagnostics-requested-visits")
                    Label(snapshotsTitle(for: diagnostics.snapshotsReceived), systemImage: "waveform.path")
                        .accessibilityIdentifier("gokan.analysis-diagnostics-snapshots")

                    if let completedVisits = diagnostics.completedVisits {
                        Label("\(completedVisits) completed visits", systemImage: "checkmark.seal")
                            .accessibilityIdentifier("gokan.analysis-diagnostics-completed-visits")
                    }

                    if let durationSeconds = diagnostics.durationSeconds {
                        Label(durationTitle(for: durationSeconds), systemImage: "timer")
                            .accessibilityIdentifier("gokan.analysis-diagnostics-duration")
                    }

                    if case .failed(let message) = diagnostics.outcome {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("gokan.analysis-diagnostics-error")
                    }
                }
            }

            Section("SGF") {
                Button {
                    isImportingSGF = true
                } label: {
                    Label("Open SGF", systemImage: "folder")
                }

                Button {
                    do {
                        exportDocument = SGFFileDocument(text: try model.exportSGFText())
                        isExportingSGF = true
                    } catch {
                        model.documentError = String(describing: error)
                    }
                } label: {
                    Label("Save SGF", systemImage: "square.and.arrow.down")
                }

                TextEditor(text: $model.sgfText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)

                Button {
                    model.loadSGFText(model.sgfText)
                } label: {
                    Label("Load SGF", systemImage: "square.and.arrow.down")
                }

                if model.exportedSGFText.isEmpty == false {
                    ScrollView(.horizontal) {
                        Text(model.exportedSGFText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 44)
                }
            }

            if let documentError = model.documentError {
                Section("Document") {
                    Label(documentError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            if let analysis = model.analysis {
                Section("Analysis") {
                    Label("\(analysis.completedVisits) visits", systemImage: "cpu")
                        .accessibilityIdentifier("gokan.analysis-visits")
                    Label(String(format: "%+.1f lead", analysis.scoreLead), systemImage: "chart.xyaxis.line")
                        .accessibilityIdentifier("gokan.analysis-score-lead")
                }
            }
        }
        .navigationTitle("Gokan")
        .listStyle(.sidebar)
        .fileImporter(
            isPresented: $isImportingSGF,
            allowedContentTypes: [.sgf, .plainText],
            allowsMultipleSelection: false,
            onCompletion: importSGF(result:)
        )
        .fileImporter(
            isPresented: $isImportingModelCatalog,
            allowedContentTypes: [.json, .plainText],
            allowsMultipleSelection: false,
            onCompletion: importModelCatalog(result:)
        )
        .fileExporter(
            isPresented: $isExportingSGF,
            document: exportDocument,
            contentType: .sgf,
            defaultFilename: "Gokan Game",
            onCompletion: exportSGF(result:)
        )
    }

    private func importSGF(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }
            model.loadSGFFile(at: url)
        case .failure(let error):
            model.documentError = error.localizedDescription
        }
    }

    private func importModelCatalog(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }
            model.loadModelCatalogFile(at: url)
        case .failure(let error):
            model.reportModelCatalogImportError(error)
        }
    }

    private func exportSGF(result: Result<URL, Error>) {
        if case .failure(let error) = result {
            model.documentError = error.localizedDescription
        }
    }

    private func metadataBinding(_ keyPath: WritableKeyPath<GameMetadata, String>) -> Binding<String> {
        Binding(
            get: {
                model.gameMetadata[keyPath: keyPath]
            },
            set: { value in
                var metadata = model.gameMetadata
                metadata[keyPath: keyPath] = value
                model.gameMetadata = metadata
            }
        )
    }

    private func moveListTitle(for item: GameMoveListItem) -> String {
        guard let move = item.move else {
            return "Root"
        }
        return "\(item.index). \(moveTitle(for: move))"
    }

    private func variationTitle(for choice: GameVariationChoice) -> String {
        "\(choice.index + 1). \(moveTitle(for: choice.move))"
    }

    private func moveTitle(for playedMove: PlayedMove) -> String {
        let color = playedMove.color.rawValue.capitalized
        switch playedMove.move {
        case .pass:
            return "\(color) pass"
        case .play(let point):
            return "\(color) \(point.x + 1), \(point.y + 1)"
        }
    }

    private var engineStatusSystemImage: String {
        switch model.engineStatus {
        case .mock:
            "testtube.2"
        case .kataGoConfigured:
            "checkmark.circle"
        case .kataGoIncomplete,
             .kataGoMissingExecutable,
             .kataGoMissingModel,
             .kataGoMissingConfig,
             .kataGoUnsupported:
            "exclamationmark.triangle"
        case .error:
            "xmark.octagon"
        }
    }

    private var engineStatusColor: Color {
        switch model.engineStatus {
        case .mock:
            .secondary
        case .kataGoConfigured:
            .green
        case .kataGoIncomplete,
             .kataGoMissingExecutable,
             .kataGoMissingModel,
             .kataGoMissingConfig,
             .kataGoUnsupported:
            .orange
        case .error:
            .red
        }
    }

    private var unknownProfileID: String? {
        let profileID = model.kataGoModelSettings.selectedProfileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard profileID.isEmpty == false,
              model.modelCatalog.profile(id: profileID) == nil else {
            return nil
        }
        return profileID
    }

    private var modelCatalogStatusTitle: String {
        switch model.modelCatalog.profiles.count {
        case 0:
            "No model catalog loaded."
        case 1:
            "1 model profile loaded."
        default:
            "\(model.modelCatalog.profiles.count) model profiles loaded."
        }
    }

    private var modelStatusSystemImage: String {
        switch model.kataGoModelStatus {
        case .profileReady, .checksumVerified:
            "checkmark.circle"
        case .notSelected, .manualPath:
            "circle"
        case .profileUnavailable, .missingCacheRoot, .missingCachedModel, .missingCachedConfig, .missingConfigPath, .checksumUnavailable:
            "exclamationmark.triangle"
        case .checksumMismatch, .verificationFailed:
            "xmark.octagon"
        }
    }

    private var modelStatusColor: Color {
        switch model.kataGoModelStatus {
        case .profileReady, .checksumVerified:
            .green
        case .notSelected, .manualPath:
            .secondary
        case .profileUnavailable, .missingCacheRoot, .missingCachedModel, .missingCachedConfig, .missingConfigPath, .checksumUnavailable:
            .orange
        case .checksumMismatch, .verificationFailed:
            .red
        }
    }

    @ViewBuilder
    private func modelProfileDetails(for profile: GokanModelProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(profile.displayName)
                .font(.headline)
                .accessibilityIdentifier("gokan.model-profile-name")
            if let description = profile.description, description.isEmpty == false {
                Text(description)
                    .foregroundStyle(.secondary)
            }
            detailRow("Model", value: profile.modelFileName)
            detailRow("Config", value: profile.defaultConfigFileName ?? "Manual config required")
            if let expectedByteCount = profile.expectedByteCount {
                detailRow("Size", value: byteCountTitle(for: expectedByteCount))
            }
            detailRow("License", value: profile.license.name)
            if profile.supportedBoardSizes.isEmpty == false {
                detailRow("Boards", value: boardSizesTitle(for: profile.supportedBoardSizes))
            }
            if profile.deviceSuitability.isEmpty == false {
                detailRow("Devices", value: deviceSuitabilityTitle(for: profile.deviceSuitability))
            }
        }
        .font(.caption)
        .accessibilityIdentifier("gokan.model-profile-details")
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func byteCountTitle(for byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func boardSizesTitle(for boardSizes: [GokanModelBoardSize]) -> String {
        boardSizes
            .map { "\($0.width)x\($0.height)" }
            .joined(separator: ", ")
    }

    private func deviceSuitabilityTitle(for suitability: [GokanDeviceSuitability]) -> String {
        suitability
            .map { item in
                let title = "\(item.platform.rawValue) \(item.tier.rawValue.capitalized)"
                if let note = item.note, note.isEmpty == false {
                    return "\(title): \(note)"
                }
                return title
            }
            .joined(separator: ", ")
    }

    private func diagnosticsOutcomeTitle(for outcome: AnalysisRunOutcome) -> String {
        switch outcome {
        case .running:
            "Running"
        case .succeeded:
            "Succeeded"
        case .failed:
            "Failed"
        case .cancelled:
            "Cancelled"
        }
    }

    private func diagnosticsOutcomeSystemImage(for outcome: AnalysisRunOutcome) -> String {
        switch outcome {
        case .running:
            "hourglass"
        case .succeeded:
            "checkmark.circle"
        case .failed:
            "xmark.octagon"
        case .cancelled:
            "pause.circle"
        }
    }

    private func diagnosticsOutcomeColor(for outcome: AnalysisRunOutcome) -> Color {
        switch outcome {
        case .running:
            .blue
        case .succeeded:
            .green
        case .failed:
            .red
        case .cancelled:
            .orange
        }
    }

    private func snapshotsTitle(for count: Int) -> String {
        count == 1 ? "1 snapshot" : "\(count) snapshots"
    }

    private func durationTitle(for durationSeconds: Double) -> String {
        if durationSeconds < 1 {
            return "\(Int((durationSeconds * 1_000).rounded())) ms"
        }

        return String(format: "%.2f s", durationSeconds)
    }
}

private struct BoardWorkspaceView: View {
    let model: GokanAppModel

    var body: some View {
        HStack(spacing: 0) {
            GoBoardView(
                board: model.game.board,
                selectedPoint: model.selectedPoint,
                selectedCandidatePoint: model.selectedAnalysisCandidatePoint,
                candidateMoves: model.analysis?.candidateMoves ?? [],
                onPlay: model.play(at:)
            )
            .padding()

            Divider()

            AnalysisPanelView(
                snapshot: model.analysis,
                error: model.analysisError,
                selectedCandidatePoint: model.selectedAnalysisCandidatePoint,
                canPlaySelectedCandidate: model.canPlaySelectedAnalysisCandidate,
                onSelectCandidate: model.selectAnalysisCandidate(_:),
                onPlayCandidate: model.playSelectedAnalysisCandidate
            )
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
        }
        .navigationTitle("Board")
    }
}

private struct AnalysisPanelView: View {
    let snapshot: AnalysisSnapshot?
    let error: String?
    let selectedCandidatePoint: BoardPoint?
    let canPlaySelectedCandidate: Bool
    let onSelectCandidate: (CandidateMove) -> Void
    let onPlayCandidate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Candidates")
                .font(.headline)

            if let error {
                ContentUnavailableView("Analysis paused", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(snapshot.candidateMoves) { move in
                        Button {
                            onSelectCandidate(move)
                        } label: {
                            CandidateMoveRow(move: move, isSelected: selectedCandidatePoint == move.point)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("gokan.candidate.\(move.point.x + 1).\(move.point.y + 1)")
                    }

                    Button {
                        onPlayCandidate()
                    } label: {
                        Label("Play Candidate", systemImage: "play.circle")
                    }
                    .disabled(canPlaySelectedCandidate == false)
                }
            } else {
                ContentUnavailableView("No analysis yet", systemImage: "sparkles")
            }

            Spacer()
        }
        .padding()
    }
}

private struct CandidateMoveRow: View {
    let move: CandidateMove
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                .frame(width: 18)

            Text("\(move.point.x + 1), \(move.point.y + 1)")
                .font(.body.monospacedDigit())
            Spacer()
            Text("\(Int(move.winRate * 100))%")
                .foregroundStyle(.secondary)
            Text("\(move.visits)")
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
