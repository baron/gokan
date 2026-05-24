// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import GokanCore
@testable import GokanEngine

@Test
func mockEngineReturnsCandidateMoves() async throws {
    let game = GameRecord(boardSize: BoardSize(width: 9, height: 9))
    let engine = MockAnalysisEngine()
    let stream = try await engine.analyze(AnalysisRequest(board: game.board, moves: game.moves, visits: 100))
    var snapshots: [AnalysisSnapshot] = []

    for try await snapshot in stream {
        snapshots.append(snapshot)
    }

    #expect(snapshots.count == 1)
    #expect(snapshots[0].candidateMoves.isEmpty == false)
    #expect(snapshots[0].completedVisits == 100)
}
