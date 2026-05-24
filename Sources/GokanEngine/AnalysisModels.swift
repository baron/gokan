// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GokanCore

public struct AnalysisRequest: Hashable, Sendable {
    public let board: GoBoard
    public let moves: [PlayedMove]
    public let visits: Int

    public init(board: GoBoard, moves: [PlayedMove], visits: Int = 400) {
        self.board = board
        self.moves = moves
        self.visits = visits
    }
}

public struct CandidateMove: Hashable, Sendable, Identifiable {
    public let id: BoardPoint
    public let point: BoardPoint
    public let policy: Double
    public let winRate: Double
    public let visits: Int

    public init(point: BoardPoint, policy: Double, winRate: Double, visits: Int) {
        self.id = point
        self.point = point
        self.policy = policy
        self.winRate = winRate
        self.visits = visits
    }
}

public struct AnalysisSnapshot: Hashable, Sendable {
    public let candidateMoves: [CandidateMove]
    public let scoreLead: Double
    public let completedVisits: Int

    public init(candidateMoves: [CandidateMove], scoreLead: Double, completedVisits: Int) {
        self.candidateMoves = candidateMoves
        self.scoreLead = scoreLead
        self.completedVisits = completedVisits
    }
}

public protocol GoAnalysisEngine: Sendable {
    func analyze(_ request: AnalysisRequest) async throws -> AsyncThrowingStream<AnalysisSnapshot, Error>
}
