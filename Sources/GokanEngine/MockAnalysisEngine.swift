// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GokanCore

public struct MockAnalysisEngine: GoAnalysisEngine {
    public init() {}

    public func analyze(_ request: AnalysisRequest) async throws -> AsyncThrowingStream<AnalysisSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let openPoints = request.board.size.points.filter { request.board[$0] == nil }
            let center = BoardPoint(
                x: request.board.size.width / 2,
                y: request.board.size.height / 2
            )

            let candidates = openPoints
                .sorted { lhs, rhs in
                    distance(lhs, center) < distance(rhs, center)
                }
                .prefix(5)
                .enumerated()
                .map { index, point in
                    CandidateMove(
                        point: point,
                        policy: max(0.05, 0.36 - Double(index) * 0.05),
                        winRate: 0.52 - Double(index) * 0.01,
                        visits: max(1, request.visits / (index + 2))
                    )
                }

            continuation.yield(
                AnalysisSnapshot(
                    candidateMoves: Array(candidates),
                    scoreLead: Double(request.moves.count % 7) - 3.0,
                    completedVisits: request.visits
                )
            )
            continuation.finish()
        }
    }

    private func distance(_ lhs: BoardPoint, _ rhs: BoardPoint) -> Int {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y)
    }
}
