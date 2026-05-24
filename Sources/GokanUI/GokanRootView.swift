// SPDX-License-Identifier: GPL-3.0-or-later

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
        .task(id: model.positionVersion) {
            await model.analyze()
        }
    }
}

private struct SidebarView: View {
    @Bindable var model: GokanAppModel

    var body: some View {
        List {
            Section("Game") {
                Label("\(model.game.board.size.width)x\(model.game.board.size.height)", systemImage: "square.grid.3x3")
                Label("\(model.game.moves.count) moves", systemImage: "list.number")
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

            Section("SGF") {
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
