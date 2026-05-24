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
