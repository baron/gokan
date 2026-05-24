// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import GokanCore
import GokanEngine

public struct GokanRootView: View {
    private let initialSGFText: String?
    @State private var model: GokanAppModel
    @State private var didLoadInitialSGFText = false

    @MainActor
    public init(initialSGFText: String? = nil, forceMockEngine: Bool = false) {
        self.initialSGFText = initialSGFText
        _model = State(initialValue: forceMockEngine ? GokanAppModel(engine: MockAnalysisEngine()) : GokanAppModel())
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
            loadInitialSGFTextIfNeeded()
        }
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

                if model.engineKind == .kataGo {
                    #if os(macOS)
                    TextField("Executable path", text: $model.kataGoSettings.executablePath)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model path", text: $model.kataGoSettings.modelPath)
                        .textFieldStyle(.roundedBorder)
                    TextField("Config path", text: $model.kataGoSettings.configPath)
                        .textFieldStyle(.roundedBorder)
                    #endif
                }

                Label(model.engineStatus.message, systemImage: engineStatusSystemImage)
                    .foregroundStyle(engineStatusColor)

                Button {
                    Task {
                        await model.analyze()
                    }
                } label: {
                    Label("Analyze Now", systemImage: "play.circle")
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
        case .kataGoIncomplete, .kataGoUnsupported:
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
        case .kataGoIncomplete, .kataGoUnsupported:
            .orange
        case .error:
            .red
        }
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
