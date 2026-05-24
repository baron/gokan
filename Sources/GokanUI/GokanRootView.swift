// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import GokanCore
import GokanEngine

public struct GokanRootView: View {
    @State private var model = GokanAppModel()

    public init() {}

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
                Label("Move \(model.game.currentMoveIndex) / \(model.game.moves.count)", systemImage: "list.number")
                Label("\(model.game.nextPlayer.rawValue.capitalized) to play", systemImage: "circle.lefthalf.filled")
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

            Section("Engine") {
                Picker("Engine", selection: $model.engineKind) {
                    ForEach(AnalysisEngineKind.allCases) { kind in
                        Text(kind.displayName)
                            .tag(kind)
                    }
                }

                if model.engineKind == .kataGo {
                    TextField("Executable path", text: $model.kataGoSettings.executablePath)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model path", text: $model.kataGoSettings.modelPath)
                        .textFieldStyle(.roundedBorder)
                    TextField("Config path", text: $model.kataGoSettings.configPath)
                        .textFieldStyle(.roundedBorder)
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
                    Label(String(format: "%+.1f lead", analysis.scoreLead), systemImage: "chart.xyaxis.line")
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

    private var engineStatusSystemImage: String {
        switch model.engineStatus {
        case .mock:
            "testtube.2"
        case .kataGoConfigured:
            "checkmark.circle"
        case .kataGoIncomplete:
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
        case .kataGoIncomplete:
            .orange
        case .error:
            .red
        }
    }
}

private struct BoardWorkspaceView: View {
    let model: GokanAppModel

    var body: some View {
        HStack(spacing: 0) {
            GoBoardView(
                board: model.game.board,
                selectedPoint: model.selectedPoint,
                candidateMoves: model.analysis?.candidateMoves ?? [],
                onPlay: model.play(at:)
            )
            .padding()

            Divider()

            AnalysisPanelView(snapshot: model.analysis, error: model.analysisError)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
        }
        .navigationTitle("Board")
    }
}

private struct AnalysisPanelView: View {
    let snapshot: AnalysisSnapshot?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Candidates")
                .font(.headline)

            if let error {
                ContentUnavailableView("Analysis paused", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(snapshot.candidateMoves) { move in
                        CandidateMoveRow(move: move)
                    }
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

    var body: some View {
        HStack {
            Text("\(move.point.x + 1), \(move.point.y + 1)")
                .font(.body.monospacedDigit())
            Spacer()
            Text("\(Int(move.winRate * 100))%")
                .foregroundStyle(.secondary)
            Text("\(move.visits)")
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }
}
