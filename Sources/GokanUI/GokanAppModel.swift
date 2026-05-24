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

    private let engine: any GoAnalysisEngine

    public init(engine: any GoAnalysisEngine = MockAnalysisEngine()) {
        self.engine = engine
    }

    public func play(at point: BoardPoint) {
        do {
            try game.play(.play(point))
            selectedPoint = point
            analysisError = nil
        } catch {
            analysisError = String(describing: error)
        }
    }

    public func analyze() async {
        do {
            let request = AnalysisRequest(board: game.board, moves: game.moves)
            let stream = try await engine.analyze(request)
            for try await snapshot in stream {
                analysis = snapshot
            }
        } catch {
            analysisError = error.localizedDescription
        }
    }
}
