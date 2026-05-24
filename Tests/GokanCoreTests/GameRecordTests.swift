// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import GokanCore

@Test
func defaultGameRecordMetadataIsEmpty() {
    let game = GameRecord()

    #expect(game.metadata == .empty)
    #expect(game.metadata.isEmpty)
}

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
func playingFromMiddleCreatesSiblingVariation() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9))
    try game.play(.play(BoardPoint(x: 4, y: 4)))
    try game.play(.play(BoardPoint(x: 4, y: 5)))
    try game.stepBackward()

    try game.play(.play(BoardPoint(x: 5, y: 5)))

    #expect(game.moves.count == 2)
    #expect(game.currentMoveIndex == 2)
    #expect(game.board[BoardPoint(x: 4, y: 5)] == nil)
    #expect(game.board[BoardPoint(x: 5, y: 5)] == .white)
    #expect(game.rootChildren[0].children.count == 2)
    #expect(game.variationChoices.count == 0)
}

@Test
func selectingVariationUpdatesBoardAndLine() throws {
    var game = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[ee](;W[ef])(;W[ff]))").gameRecord()
    try game.stepBackward()

    try game.selectVariation(at: 1)

    #expect(game.currentMoveIndex == 2)
    #expect(game.moves[1].move == .play(BoardPoint(x: 5, y: 5)))
    #expect(game.board[BoardPoint(x: 4, y: 5)] == nil)
    #expect(game.board[BoardPoint(x: 5, y: 5)] == .white)
}

@Test
func metadataSurvivesReviewNavigationAndVariationSelection() throws {
    let metadata = GameMetadata(
        blackPlayerName: "Black",
        whitePlayerName: "White",
        komi: "6.5",
        result: "W+2.5",
        gameName: "Review",
        event: "Testing",
        date: "2026-05-25"
    )
    var game = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[ee](;W[ef])(;W[ff]))").gameRecord()
    game.metadata = metadata

    try game.stepBackward()
    try game.selectVariation(at: 1)
    try game.goToStart()
    try game.goToEnd()

    #expect(game.metadata == metadata)
    #expect(game.moves[1].move == .play(BoardPoint(x: 5, y: 5)))
}

@Test
func variationChoicesDescribeContinuationsAtCurrentNode() throws {
    var game = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[ee](;W[ef])(;W[ff]))").gameRecord()
    try game.stepBackward()

    #expect(game.variationChoices.count == 2)
    #expect(game.variationChoices[0].isSelected)
    #expect(game.variationChoices[1].move.move == .play(BoardPoint(x: 5, y: 5)))
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

@Test
func emptyGameMoveListContainsCurrentRoot() {
    let game = GameRecord(boardSize: BoardSize(width: 9, height: 9))

    #expect(game.moveListItems.count == 1)
    #expect(game.moveListItems[0].index == 0)
    #expect(game.moveListItems[0].move == nil)
    #expect(game.moveListItems[0].isCurrent)
}

@Test
func moveListCurrentMarkerTracksReviewedPosition() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9))
    try game.play(.play(BoardPoint(x: 4, y: 4)))
    try game.play(.play(BoardPoint(x: 4, y: 5)))

    try game.stepBackward()

    #expect(game.moveListItems.map(\.index) == [0, 1, 2])
    #expect(game.moveListItems.map(\.isCurrent) == [false, true, false])
}

@Test
func passMovesAppearInMoveList() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9))
    try game.play(.pass)

    #expect(game.moveListItems.count == 2)
    #expect(game.moveListItems[1].move?.move == .pass)
    #expect(game.moveListItems[1].isCurrent)
}

@Test
func moveListFollowsSelectedVariationWithoutFlatteningBranches() throws {
    var game = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[ee](;W[ef])(;W[ff]))").gameRecord()

    #expect(game.moveListItems.compactMap(\.move?.move) == [
        .play(BoardPoint(x: 4, y: 4)),
        .play(BoardPoint(x: 4, y: 5))
    ])

    try game.stepBackward()
    try game.selectVariation(at: 1)

    #expect(game.moveListItems.compactMap(\.move?.move) == [
        .play(BoardPoint(x: 4, y: 4)),
        .play(BoardPoint(x: 5, y: 5))
    ])
    #expect(game.moveListItems.map(\.isCurrent) == [false, false, true])
}

@Test
func immediateSimpleKoRecaptureIsRejected() throws {
    var game = try gameWithSimpleKoCapture()
    let boardAfterCapture = game.board
    let moveIndexAfterCapture = game.currentMoveIndex

    #expect(throws: BoardError.simpleKo) {
        try game.play(.play(BoardPoint(x: 2, y: 2)))
    }

    #expect(game.board == boardAfterCapture)
    #expect(game.currentMoveIndex == moveIndexAfterCapture)
    #expect(game.board[BoardPoint(x: 2, y: 1)] == .black)
    #expect(game.board[BoardPoint(x: 2, y: 2)] == nil)
}

@Test
func passesBreakSimpleKoRestriction() throws {
    var game = try gameWithSimpleKoCapture()

    try game.play(.pass)
    try game.play(.pass)
    try game.play(.play(BoardPoint(x: 2, y: 2)))

    #expect(game.board[BoardPoint(x: 2, y: 2)] == .white)
    #expect(game.board[BoardPoint(x: 2, y: 1)] == nil)
}

@Test
func explicitMovesRejectSamePlayerAfterPass() throws {
    var game = try gameWithSimpleKoCapture()
    try game.play(PlayedMove(color: .white, move: .pass))

    #expect(throws: BoardError.wrongPlayer(expected: .black, actual: .white)) {
        try game.play(PlayedMove(color: .white, move: .play(BoardPoint(x: 2, y: 2))))
    }
}

@Test
func futureVariationPassDoesNotBreakSimpleKoAtParent() throws {
    var game = try gameWithSimpleKoCapture()
    try game.play(.pass)
    try game.stepBackward()

    #expect(throws: BoardError.simpleKo) {
        try game.play(.play(BoardPoint(x: 2, y: 2)))
    }

    #expect(game.variationChoices.count == 1)
}

private func gameWithSimpleKoCapture() throws -> GameRecord {
    var game = GameRecord(boardSize: BoardSize(width: 5, height: 5))
    try game.play(.play(BoardPoint(x: 1, y: 2)))
    try game.play(.play(BoardPoint(x: 2, y: 2)))
    try game.play(.play(BoardPoint(x: 3, y: 2)))
    try game.play(.play(BoardPoint(x: 1, y: 1)))
    try game.play(.play(BoardPoint(x: 2, y: 3)))
    try game.play(.play(BoardPoint(x: 3, y: 1)))
    try game.play(.pass)
    try game.play(.play(BoardPoint(x: 2, y: 0)))
    try game.play(.play(BoardPoint(x: 2, y: 1)))
    return game
}
