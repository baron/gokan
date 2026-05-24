// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GokanCore
import GokanEngine
import Observation

@MainActor
@Observable
public final class GokanAppModel {
    public var game = GameRecord()
    public var selectedPoint: BoardPoint?
    public var analysis: AnalysisSnapshot?
    public var analysisError: String?
    public var documentError: String?
    public var sgfText = "" {
        didSet {
            guard sgfText != oldValue else {
                return
            }
            documentError = nil
            exportedSGFText = ""
        }
    }
    public var exportedSGFText = ""
    public private(set) var positionVersion = 0

    private let engine: any GoAnalysisEngine

    public init(engine: any GoAnalysisEngine = MockAnalysisEngine()) {
        self.engine = engine
    }

    public func play(at point: BoardPoint) {
        do {
            try game.play(.play(point))
            positionDidChange(selectedPoint: point, clearDocumentText: true)
        } catch {
            analysisError = String(describing: error)
        }
    }

    public func pass() {
        do {
            try game.play(.pass)
            positionDidChange(selectedPoint: nil, clearDocumentText: true)
        } catch {
            analysisError = String(describing: error)
        }
    }

    public func newGame(boardSize: BoardSize = .standard) {
        game = GameRecord(boardSize: boardSize)
        sgfText = ""
        exportedSGFText = ""
        positionDidChange(selectedPoint: nil, clearDocumentText: false)
    }

    public func loadSGFText(_ text: String) {
        do {
            let document = try SGFDocument.parse(text)
            let nextGame = try document.gameRecord()
            game = nextGame
            sgfText = text
            exportedSGFText = ""
            positionDidChange(selectedPoint: nil, clearDocumentText: false)
        } catch {
            documentError = String(describing: error)
        }
    }

    @discardableResult
    public func exportSGFText() throws -> String {
        let text = try SGFDocument(game: game).serialize()
        exportedSGFText = text
        documentError = nil
        return text
    }

    public func analyze() async {
        let version = positionVersion
        let currentGame = game
        do {
            let request = AnalysisRequest(board: currentGame.board, moves: currentGame.moves)
            let stream = try await engine.analyze(request)
            for try await snapshot in stream {
                guard Task.isCancelled == false, version == positionVersion else {
                    return
                }
                analysis = snapshot
            }
        } catch {
            guard Task.isCancelled == false, version == positionVersion else {
                return
            }
            analysisError = error.localizedDescription
        }
    }

    private func positionDidChange(selectedPoint: BoardPoint?, clearDocumentText: Bool) {
        self.selectedPoint = selectedPoint
        analysis = nil
        analysisError = nil
        documentError = nil
        if clearDocumentText {
            sgfText = ""
            exportedSGFText = ""
        }
        positionVersion += 1
    }
}
