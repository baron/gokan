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

    public init(boardSize: BoardSize = .standard) {
        self.board = GoBoard(size: boardSize)
        self.moves = []
        self.nextPlayer = .black
    }

    public mutating func play(_ move: Move) throws {
        switch move {
        case .play(let point):
            board = try board.placing(nextPlayer, at: point)
        case .pass:
            break
        }

        moves.append(PlayedMove(color: nextPlayer, move: move))
        nextPlayer = nextPlayer.opponent
    }
}
