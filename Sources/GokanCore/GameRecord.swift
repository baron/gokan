// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct PlayedMove: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let color: StoneColor
    public let move: Move

    public init(id: UUID = UUID(), color: StoneColor, move: Move) {
        self.id = id
        self.color = color
        self.move = move
    }
}

public struct GameRecord: Hashable, Sendable {
    public private(set) var board: GoBoard
    public private(set) var moves: [PlayedMove]
    public private(set) var nextPlayer: StoneColor
    public private(set) var currentMoveIndex: Int

    public init(boardSize: BoardSize = .standard) {
        self.board = GoBoard(size: boardSize)
        self.moves = []
        self.nextPlayer = .black
        self.currentMoveIndex = 0
    }

    public var appliedMoves: [PlayedMove] {
        Array(moves.prefix(currentMoveIndex))
    }

    public var canStepBackward: Bool {
        currentMoveIndex > 0
    }

    public var canStepForward: Bool {
        currentMoveIndex < moves.count
    }

    public mutating func play(_ move: Move) throws {
        truncateFutureMoves()

        switch move {
        case .play(let point):
            board = try board.placing(nextPlayer, at: point)
        case .pass:
            break
        }

        moves.append(PlayedMove(color: nextPlayer, move: move))
        currentMoveIndex = moves.count
        nextPlayer = nextPlayer.opponent
    }

    public mutating func play(_ playedMove: PlayedMove) throws {
        truncateFutureMoves()

        switch playedMove.move {
        case .play(let point):
            board = try board.placing(playedMove.color, at: point)
        case .pass:
            break
        }

        moves.append(playedMove)
        currentMoveIndex = moves.count
        nextPlayer = playedMove.color.opponent
    }

    public mutating func stepBackward() throws {
        try goToMove(currentMoveIndex - 1)
    }

    public mutating func stepForward() throws {
        try goToMove(currentMoveIndex + 1)
    }

    public mutating func goToStart() throws {
        try goToMove(0)
    }

    public mutating func goToEnd() throws {
        try goToMove(moves.count)
    }

    public mutating func goToMove(_ moveIndex: Int) throws {
        let clampedIndex = min(max(moveIndex, 0), moves.count)
        board = GoBoard(size: board.size)

        for playedMove in moves.prefix(clampedIndex) {
            switch playedMove.move {
            case .play(let point):
                board = try board.placing(playedMove.color, at: point)
            case .pass:
                break
            }
        }

        currentMoveIndex = clampedIndex
        nextPlayer = nextPlayerAfterMove(at: clampedIndex)
    }

    private mutating func truncateFutureMoves() {
        if currentMoveIndex < moves.count {
            moves.removeSubrange(currentMoveIndex..<moves.count)
        }
    }

    private func nextPlayerAfterMove(at moveIndex: Int) -> StoneColor {
        if moveIndex < moves.count {
            return moves[moveIndex].color
        }
        return moves.prefix(moveIndex).last?.color.opponent ?? .black
    }
}
