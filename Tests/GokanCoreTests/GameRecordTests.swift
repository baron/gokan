// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import GokanCore

@Test
func steppingBackwardRestoresPreviousBoard() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9))
    try game.play(.play(BoardPoint(x: 4, y: 4)))
    try game.play(.play(BoardPoint(x: 4, y: 5)))

    try game.stepBackward()

    #expect(game.currentMoveIndex == 1)
    #expect(game.board[BoardPoint(x: 4, y: 4)] == .black)
    #expect(game.board[BoardPoint(x: 4, y: 5)] == nil)
    #expect(game.nextPlayer == .white)
}

@Test
func steppingForwardReappliesNextMove() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9))
    try game.play(.play(BoardPoint(x: 4, y: 4)))
    try game.play(.play(BoardPoint(x: 4, y: 5)))
    try game.stepBackward()

    try game.stepForward()

    #expect(game.currentMoveIndex == 2)
    #expect(game.board[BoardPoint(x: 4, y: 5)] == .white)
    #expect(game.nextPlayer == .black)
}

@Test
func goToStartLeavesEmptyBoardAndFirstMovePlayer() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9))
    try game.play(PlayedMove(color: .white, move: .play(BoardPoint(x: 4, y: 4))))
    try game.play(PlayedMove(color: .black, move: .play(BoardPoint(x: 4, y: 5))))

    try game.goToStart()

    #expect(game.currentMoveIndex == 0)
    #expect(game.board.occupiedPoints.isEmpty)
    #expect(game.nextPlayer == .white)
}

@Test
func goToEndRestoresFinalBoard() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9))
    try game.play(.play(BoardPoint(x: 4, y: 4)))
    try game.play(.pass)
    try game.goToStart()

    try game.goToEnd()

    #expect(game.currentMoveIndex == 2)
    #expect(game.board[BoardPoint(x: 4, y: 4)] == .black)
    #expect(game.nextPlayer == .black)
}

@Test
func playingFromMiddleTruncatesFutureMoves() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9))
    try game.play(.play(BoardPoint(x: 4, y: 4)))
    try game.play(.play(BoardPoint(x: 4, y: 5)))
    try game.stepBackward()

    try game.play(.play(BoardPoint(x: 5, y: 5)))

    #expect(game.moves.count == 2)
    #expect(game.currentMoveIndex == 2)
    #expect(game.board[BoardPoint(x: 4, y: 5)] == nil)
    #expect(game.board[BoardPoint(x: 5, y: 5)] == .white)
}

@Test
func passMovesParticipateInCursorMovement() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9))
    try game.play(.play(BoardPoint(x: 4, y: 4)))
    try game.play(.pass)

    try game.stepBackward()

    #expect(game.currentMoveIndex == 1)
    #expect(game.nextPlayer == .white)

    try game.stepForward()

    #expect(game.currentMoveIndex == 2)
    #expect(game.nextPlayer == .black)
}
