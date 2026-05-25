// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GokanCore

public struct AnalysisRequest: Hashable, Sendable {
    public static let defaultVisits = 400

    public let initialBoard: GoBoard
    public let board: GoBoard
    public let moves: [PlayedMove]
    public let nextPlayer: StoneColor
    public let visits: Int

    public init(
        board: GoBoard,
        moves: [PlayedMove],
        nextPlayer: StoneColor? = nil,
        visits: Int = Self.defaultVisits
    ) {
        self.init(
            initialBoard: GoBoard(size: board.size),
            board: board,
            moves: moves,
            nextPlayer: nextPlayer ?? moves.first?.color ?? .black,
            visits: visits
        )
    }

    public init(
        initialBoard: GoBoard,
        board: GoBoard,
        moves: [PlayedMove],
        nextPlayer: StoneColor = .black,
        visits: Int = Self.defaultVisits
    ) {
        precondition(initialBoard.size == board.size)
        self.initialBoard = initialBoard
        self.board = board
        self.moves = moves
        self.nextPlayer = nextPlayer
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
