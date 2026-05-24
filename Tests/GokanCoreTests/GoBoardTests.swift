// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import GokanCore

@Test
func placingStoneOccupiesPoint() throws {
    let point = BoardPoint(x: 3, y: 3)
    let board = try GoBoard(size: BoardSize(width: 9, height: 9)).placing(.black, at: point)

    #expect(board[point] == .black)
}

@Test
func captureRemovesSurroundedStone() throws {
    let white = BoardPoint(x: 1, y: 1)
    var board = GoBoard(size: BoardSize(width: 5, height: 5))

    board = try board.placing(.white, at: white)
    board = try board.placing(.black, at: BoardPoint(x: 0, y: 1))
    board = try board.placing(.black, at: BoardPoint(x: 2, y: 1))
    board = try board.placing(.black, at: BoardPoint(x: 1, y: 0))
    board = try board.placing(.black, at: BoardPoint(x: 1, y: 2))

    #expect(board[white] == nil)
}

@Test
func suicideMoveIsRejected() throws {
    var board = GoBoard(size: BoardSize(width: 5, height: 5))
    let point = BoardPoint(x: 1, y: 1)

    board = try board.placing(.black, at: BoardPoint(x: 0, y: 1))
    board = try board.placing(.black, at: BoardPoint(x: 2, y: 1))
    board = try board.placing(.black, at: BoardPoint(x: 1, y: 0))
    board = try board.placing(.black, at: BoardPoint(x: 1, y: 2))

    #expect(throws: BoardError.suicide) {
        _ = try board.placing(.white, at: point)
    }
}
