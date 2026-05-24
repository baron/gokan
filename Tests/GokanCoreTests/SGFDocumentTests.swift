// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import GokanCore

@Test
func sgfCoordinatesRoundTrip() throws {
    let point = BoardPoint(x: 3, y: 16)

    let encoded = try SGFCoordinates.encode(point)
    let decoded = try SGFCoordinates.decode(encoded)

    #expect(encoded == "dq")
    #expect(decoded == point)
}

@Test
func serializesGameRecordAsSgf() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9))
    try game.play(.play(BoardPoint(x: 4, y: 4)))
    try game.play(.pass)

    let sgf = try SGFDocument(game: game).serialize()

    #expect(sgf == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9];B[ee];W[])\n")
}

@Test
func serializesRectangularBoardSizeAsSgf() throws {
    let document = SGFDocument(boardSize: BoardSize(width: 9, height: 13))

    let sgf = try document.serialize()

    #expect(sgf == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9:13])\n")
    #expect(try SGFDocument.parse(sgf).boardSize == BoardSize(width: 9, height: 13))
}

@Test
func parsesSimpleSgfIntoGameRecord() throws {
    let document = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[ee];W[ef];B[])")
    let game = try document.gameRecord()

    #expect(document.boardSize == BoardSize(width: 9, height: 9))
    #expect(game.moves.count == 3)
    #expect(game.currentMoveIndex == 3)
    #expect(game.board[BoardPoint(x: 4, y: 4)] == .black)
    #expect(game.board[BoardPoint(x: 4, y: 5)] == .white)
}

@Test
func serializesFullGameRecordWhileReviewingEarlierMove() throws {
    var game = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[ee];W[ef])").gameRecord()
    try game.stepBackward()

    let sgf = try SGFDocument(game: game).serialize()

    #expect(game.currentMoveIndex == 1)
    #expect(sgf == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9];B[ee];W[ef])\n")
}

@Test
func parsesSgfVariationsIntoGameTree() throws {
    let document = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[ee](;W[ef])(;W[ff]))")
    var game = try document.gameRecord()

    try game.stepBackward()

    #expect(game.rootChildren.count == 1)
    #expect(game.rootChildren[0].children.count == 2)
    #expect(game.variationChoices.count == 2)
    #expect(game.variationChoices[1].move.move == .play(BoardPoint(x: 5, y: 5)))
}

@Test
func serializesGameTreeVariationsAsSgfBranches() throws {
    var game = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[ee];W[ef])").gameRecord()
    try game.stepBackward()
    try game.play(.play(BoardPoint(x: 5, y: 5)))

    let sgf = try SGFDocument(game: game).serialize()

    #expect(sgf == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9];B[ee](;W[ef])(;W[ff]))\n")
}

@Test
func parsesWhiteFirstSgfUsingStoredMoveColors() throws {
    let document = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];W[ee];B[ef])")
    let game = try document.gameRecord()

    #expect(game.moves.count == 2)
    #expect(game.moves[0].color == .white)
    #expect(game.board[BoardPoint(x: 4, y: 4)] == .white)
    #expect(game.board[BoardPoint(x: 4, y: 5)] == .black)
    #expect(game.nextPlayer == .white)
}

@Test
func parserRejectsIllegalSgfMove() throws {
    #expect(throws: SGFDocumentError.illegalMove(moveNumber: 2, .occupiedPoint)) {
        _ = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[aa];W[aa])")
    }
}

@Test
func parserRejectsTrailingContent() throws {
    #expect(throws: SGFDocumentError.invalidSyntax) {
        _ = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[aa]) junk")
    }
}

@Test
func parserReportsVariationErrorsAtVariationDepth() throws {
    #expect(throws: SGFDocumentError.illegalMove(moveNumber: 2, .occupiedPoint)) {
        _ = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[aa](;W[bb])(;W[aa]))")
    }
}

@Test
func parserRejectsImmediateSimpleKoRecapture() throws {
    #expect(throws: SGFDocumentError.illegalMove(moveNumber: 10, .simpleKo)) {
        _ = try SGFDocument.parse("(;GM[1]FF[4]SZ[5];B[bc];W[cc];B[dc];W[bb];B[cd];W[db];B[];W[ca];B[cb];W[cc])")
    }
}

@Test
func parserAllowsKoRecaptureAfterInterveningPasses() throws {
    let document = try SGFDocument.parse("(;GM[1]FF[4]SZ[5];B[bc];W[cc];B[dc];W[bb];B[cd];W[db];B[];W[ca];B[cb];W[];B[];W[cc])")
    let game = try document.gameRecord()

    #expect(game.board[BoardPoint(x: 2, y: 2)] == .white)
    #expect(game.board[BoardPoint(x: 2, y: 1)] == nil)
}

@Test
func parserRejectsSamePlayerMoveAfterPass() throws {
    #expect(throws: SGFDocumentError.illegalMove(moveNumber: 11, .wrongPlayer(expected: .black, actual: .white))) {
        _ = try SGFDocument.parse("(;GM[1]FF[4]SZ[5];B[bc];W[cc];B[dc];W[bb];B[cd];W[db];B[];W[ca];B[cb];W[];W[cc])")
    }
}

@Test
func parserKeepsKoHistoryVariationLocal() throws {
    #expect(throws: SGFDocumentError.illegalMove(moveNumber: 10, .simpleKo)) {
        _ = try SGFDocument.parse("(;GM[1]FF[4]SZ[5];B[bc];W[cc];B[dc];W[bb];B[cd];W[db];B[];W[ca];B[cb](;W[])(;W[cc]))")
    }
}
