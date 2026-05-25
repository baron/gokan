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
func parsesRootMetadataIntoGameRecord() throws {
    let document = try SGFDocument.parse(
        "(;GM[1]FF[4]SZ[9]GN[Game 1]EV[Test Event]DT[2026-05-25]PB[Black Name]PW[White Name]KM[6.5]RE[B+R];B[ee])"
    )
    let game = try document.gameRecord()

    let metadata = GameMetadata(
        blackPlayerName: "Black Name",
        whitePlayerName: "White Name",
        komi: "6.5",
        result: "B+R",
        gameName: "Game 1",
        event: "Test Event",
        date: "2026-05-25"
    )
    #expect(document.metadata == metadata)
    #expect(game.metadata == metadata)
}

@Test
func serializesGameMetadataInStableOrder() throws {
    let document = SGFDocument(
        boardSize: BoardSize(width: 9, height: 9),
        moves: [PlayedMove(color: .black, move: .play(BoardPoint(x: 4, y: 4)))],
        metadata: GameMetadata(
            blackPlayerName: "Black Name",
            whitePlayerName: "White Name",
            komi: "6.5",
            result: "B+R",
            gameName: "Game 1",
            event: "Test Event",
            date: "2026-05-25"
        )
    )

    let sgf = try document.serialize()

    #expect(
        sgf
            == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9]GN[Game 1]EV[Test Event]DT[2026-05-25]PB[Black Name]PW[White Name]KM[6.5]RE[B+R];B[ee])\n"
    )
}

@Test
func metadataValuesEscapeAndUnescapeSgfCharacters() throws {
    let document = SGFDocument(
        boardSize: BoardSize(width: 9, height: 9),
        metadata: GameMetadata(gameName: #"Title \ One ] Two"#)
    )

    let sgf = try document.serialize()
    let parsed = try SGFDocument.parse(sgf)

    #expect(sgf == #"(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9]GN[Title \\ One \] Two])"# + "\n")
    #expect(parsed.metadata.gameName == #"Title \ One ] Two"#)
}

@Test
func parsesRootCommentIntoGameRecord() throws {
    let document = try SGFDocument.parse("(;GM[1]FF[4]SZ[9]C[Root note];B[ee])")
    let game = try document.gameRecord()

    #expect(document.rootComment == "Root note")
    #expect(game.rootComment == "Root note")
    #expect(game.currentNodeComment.isEmpty)
}

@Test
func parsesMoveCommentsIntoGameTree() throws {
    let document = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[ee]C[Black note];W[ef]C[White note])")
    var game = try document.gameRecord()

    #expect(game.currentNodeComment == "White note")

    try game.stepBackward()

    #expect(game.currentNodeComment == "Black note")
}

@Test
func foldsCommentOnlyMainLineNodesIntoRepresentableComments() throws {
    let document = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];C[Root continuation];B[ee];C[Black follow-up];W[ef])")
    var game = try document.gameRecord()

    #expect(game.rootComment == "Root continuation")
    #expect(game.currentNodeComment.isEmpty)

    try game.stepBackward()

    #expect(game.currentNodeComment == "Black follow-up")
}

@Test
func foldsCommentOnlyVariationPrefixesIntoFirstBranchMove() throws {
    let document = try SGFDocument.parse(
        "(;GM[1]FF[4]SZ[9];B[ee](;C[First branch note];W[ef])(;C[Second branch note];W[ff]))"
    )
    var game = try document.gameRecord()

    #expect(game.currentNodeComment == "First branch note")

    try game.stepBackward()
    try game.selectVariation(at: 1)

    #expect(game.currentNodeComment == "Second branch note")
}

@Test
func serializesRootAndMoveCommentsAsSgf() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9), rootComment: "Root note")
    try game.play(.play(BoardPoint(x: 4, y: 4)))
    game.currentNodeComment = "Black note"

    let sgf = try SGFDocument(game: game).serialize()

    #expect(sgf == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9]C[Root note];B[ee]C[Black note])\n")
}

@Test
func commentValuesEscapeAndUnescapeSgfCharacters() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9), rootComment: #"Root \ One ] Two"#)
    try game.play(.play(BoardPoint(x: 4, y: 4)))
    game.currentNodeComment = #"Move \ Three ] Four"#

    let sgf = try SGFDocument(game: game).serialize()
    let parsed = try SGFDocument.parse(sgf)
    let parsedGame = try parsed.gameRecord()

    #expect(
        sgf == #"(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9]C[Root \\ One \] Two];B[ee]C[Move \\ Three \] Four])"# + "\n"
    )
    #expect(parsed.rootComment == #"Root \ One ] Two"#)
    #expect(parsedGame.rootChildren[0].comment == #"Move \ Three ] Four"#)
}

@Test
func variationCommentsRoundTripWithBranches() throws {
    let document = try SGFDocument.parse(
        "(;GM[1]FF[4]SZ[9]C[Root];B[ee]C[Main](;W[ef]C[First branch])(;W[ff]C[Second branch]))"
    )

    let sgf = try document.serialize()
    let reparsed = try SGFDocument.parse(sgf)

    #expect(
        sgf == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9]C[Root];B[ee]C[Main](;W[ef]C[First branch])(;W[ff]C[Second branch]))\n"
    )
    #expect(reparsed.rootChildren[0].comment == "Main")
    #expect(reparsed.rootChildren[0].children[0].comment == "First branch")
    #expect(reparsed.rootChildren[0].children[1].comment == "Second branch")
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
func parsesRootSetupStonesIntoInitialBoard() throws {
    let document = try SGFDocument.parse("(;GM[1]FF[4]SZ[9]AB[cc][gg]AW[ee];W[ef])")
    var game = try document.gameRecord()

    #expect(document.initialBoard[BoardPoint(x: 2, y: 2)] == .black)
    #expect(document.initialBoard[BoardPoint(x: 6, y: 6)] == .black)
    #expect(document.initialBoard[BoardPoint(x: 4, y: 4)] == .white)
    #expect(game.initialBoard == document.initialBoard)
    #expect(game.board[BoardPoint(x: 4, y: 5)] == .white)

    try game.goToStart()

    #expect(game.board == document.initialBoard)
}

@Test
func serializesRootSetupStonesBeforeMetadataAndComments() throws {
    let document = SGFDocument(
        initialBoard: GoBoard(
            size: BoardSize(width: 9, height: 9),
            stones: [
                BoardPoint(x: 2, y: 2): .black,
                BoardPoint(x: 6, y: 6): .black,
                BoardPoint(x: 4, y: 4): .white,
            ]
        ),
        rootChildren: [
            GameTreeNode(playedMove: PlayedMove(color: .white, move: .play(BoardPoint(x: 4, y: 5))))
        ],
        metadata: GameMetadata(gameName: "Setup"),
        rootComment: "Root note"
    )

    let sgf = try document.serialize()
    let parsed = try SGFDocument.parse(sgf)

    #expect(sgf == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9]AB[cc][gg]AW[ee]GN[Setup]C[Root note];W[ef])\n")
    #expect(parsed.initialBoard == document.initialBoard)
    #expect(parsed.metadata == document.metadata)
    #expect(parsed.rootComment == document.rootComment)
    #expect(parsed.moves.map(\.color) == document.moves.map(\.color))
    #expect(parsed.moves.map(\.move) == document.moves.map(\.move))
}

@Test
func rejectsDuplicateRootSetupStones() throws {
    #expect(throws: SGFDocumentError.duplicateSetupStone(BoardPoint(x: 2, y: 2))) {
        _ = try SGFDocument.parse("(;GM[1]FF[4]SZ[9]AB[cc]AW[cc])")
    }
}

@Test
func rejectsUnsupportedSetupStonesOutsideRoot() throws {
    #expect(throws: SGFDocumentError.unsupportedSetupProperty("AB")) {
        _ = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[ee]AB[cc])")
    }
}

@Test
func rejectsRootSetupRemovalsUntilNodeEditingIsSupported() throws {
    #expect(throws: SGFDocumentError.unsupportedSetupProperty("AE")) {
        _ = try SGFDocument.parse("(;GM[1]FF[4]SZ[9]AE[cc])")
    }
}

@Test
func rejectsSetupPlayerUntilTurnStateIsSupported() throws {
    #expect(throws: SGFDocumentError.unsupportedSetupProperty("PL")) {
        _ = try SGFDocument.parse("(;GM[1]FF[4]SZ[9]AB[cc]PL[W])")
    }
}

@Test
func rejectsCompressedRootSetupPointListsUntilExpansionIsSupported() throws {
    #expect(throws: SGFDocumentError.invalidSetupStone(property: "AB", value: "aa:cc")) {
        _ = try SGFDocument.parse("(;GM[1]FF[4]SZ[9]AB[aa:cc])")
    }
}

@Test
func rejectsSetupPropertiesInsideVariations() throws {
    #expect(throws: SGFDocumentError.unsupportedSetupProperty("AW")) {
        _ = try SGFDocument.parse("(;GM[1]FF[4]SZ[9];B[ee](;W[ef])(;AW[cc];W[ff]))")
    }
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
