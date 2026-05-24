// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum GameRules {
    static func applying(
        _ playedMove: PlayedMove,
        to board: GoBoard,
        simpleKoReferenceBoard: GoBoard?
    ) throws -> GoBoard {
        switch playedMove.move {
        case .play(let point):
            let nextBoard = try board.placing(playedMove.color, at: point)
            if nextBoard == simpleKoReferenceBoard {
                throw BoardError.simpleKo
            }
            return nextBoard
        case .pass:
            return board
        }
    }
}
