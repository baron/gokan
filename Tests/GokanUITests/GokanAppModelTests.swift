// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GokanCore
import GokanEngine
import GokanModels
@testable import GokanUI

@MainActor
@Test
func newGameResetsPositionAndDocumentState() throws {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.play(at: BoardPoint(x: 3, y: 3))
    model.sgfText = "(;GM[1]FF[4]SZ[9];B[ee])"
    model.exportedSGFText = try model.exportSGFText()

    model.newGame(boardSize: BoardSize(width: 9, height: 9))

    #expect(model.game.board.size == BoardSize(width: 9, height: 9))
    #expect(model.game.moves.isEmpty)
    #expect(model.selectedPoint == nil)
    #expect(model.analysis == nil)
    #expect(model.analysisError == nil)
    #expect(model.documentError == nil)
    #expect(model.sgfText.isEmpty)
    #expect(model.exportedSGFText.isEmpty)
}

@MainActor
@Test
func passAddsMoveAndFlipsNextPlayer() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())

    model.pass()

    #expect(model.game.moves.count == 1)
    #expect(model.game.moves[0].move == .pass)
    #expect(model.game.nextPlayer == .white)
    #expect(model.selectedPoint == nil)
    #expect(model.analysis == nil)
}

@MainActor
@Test
func playClearsStaleDocumentTextAndExport() throws {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.sgfText = "(;GM[1]FF[4]SZ[9])"
    model.exportedSGFText = "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9])\n"

    model.play(at: BoardPoint(x: 3, y: 3))

    #expect(model.sgfText.isEmpty)
    #expect(model.exportedSGFText.isEmpty)
    #expect(model.documentError == nil)
}

@MainActor
@Test
func loadSGFTextReplacesCurrentGameTransactionally() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.play(at: BoardPoint(x: 0, y: 0))

    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee];W[ef])")

    #expect(model.game.board.size == BoardSize(width: 9, height: 9))
    #expect(model.game.moves.count == 2)
    #expect(model.game.currentMoveIndex == 2)
    #expect(model.game.board[BoardPoint(x: 4, y: 4)] == .black)
    #expect(model.game.board[BoardPoint(x: 4, y: 5)] == .white)
    #expect(model.documentError == nil)
    #expect(model.analysis == nil)
}

@MainActor
@Test
func loadingSGFTextExposesSetupStones() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())

    model.loadSGFText("(;GM[1]FF[4]SZ[9]AB[cc]AW[ee];W[ef])")

    #expect(model.game.initialBoard[BoardPoint(x: 2, y: 2)] == .black)
    #expect(model.game.initialBoard[BoardPoint(x: 4, y: 4)] == .white)
    #expect(model.game.board[BoardPoint(x: 2, y: 2)] == .black)
    #expect(model.game.board[BoardPoint(x: 4, y: 4)] == .white)
    #expect(model.game.board[BoardPoint(x: 4, y: 5)] == .white)
    #expect(model.documentError == nil)
}

@MainActor
@Test
func analysisRequestIncludesInitialSetupBoard() async throws {
    let engine = RecordingAnalysisEngine()
    let model = GokanAppModel(engine: engine)
    model.loadSGFText("(;GM[1]FF[4]SZ[9]AB[cc]AW[ee];W[ef])")

    await model.analyze()

    let request = try #require(engine.lastRequest)
    #expect(request.initialBoard[BoardPoint(x: 2, y: 2)] == .black)
    #expect(request.initialBoard[BoardPoint(x: 4, y: 4)] == .white)
    #expect(request.board[BoardPoint(x: 4, y: 5)] == .white)
    #expect(request.moves == model.game.appliedMoves)
}

@MainActor
@Test
func rootSetupAnalysisRequestUsesCurrentSideToMove() async throws {
    let engine = RecordingAnalysisEngine()
    let model = GokanAppModel(engine: engine)
    model.loadSGFText("(;GM[1]FF[4]SZ[9]AB[cc];W[ef])")
    model.goToFirstMove()

    await model.analyze()

    let request = try #require(engine.lastRequest)
    #expect(model.game.currentMoveIndex == 0)
    #expect(model.game.nextPlayer == .white)
    #expect(request.moves.isEmpty)
    #expect(request.nextPlayer == .white)
}

@MainActor
@Test
func loadSGFTextReportsErrorAndPreservesCurrentGame() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.play(at: BoardPoint(x: 0, y: 0))
    let originalGame = model.game

    model.loadSGFText("not sgf")

    #expect(model.game == originalGame)
    #expect(model.documentError != nil)
}

@MainActor
@Test
func editingSGFTextClearsStaleDocumentErrorAndExport() throws {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("not sgf")
    model.exportedSGFText = try model.exportSGFText()

    model.sgfText = "(;GM[1]FF[4]SZ[9])"

    #expect(model.documentError == nil)
    #expect(model.exportedSGFText.isEmpty)
}

@MainActor
@Test
func exportSGFTextSerializesCurrentGame() throws {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.newGame(boardSize: BoardSize(width: 9, height: 9))
    model.play(at: BoardPoint(x: 4, y: 4))
    model.pass()

    let text = try model.exportSGFText()

    #expect(text == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9];B[ee];W[])\n")
    #expect(model.exportedSGFText == text)
    #expect(model.documentError == nil)
}

@MainActor
@Test
func loadingSGFTextExposesGameMetadata() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())

    model.loadSGFText("(;GM[1]FF[4]SZ[9]GN[Title]EV[Event]DT[2026-05-25]PB[Black]PW[White]KM[6.5]RE[B+R];B[ee])")

    #expect(model.gameMetadata.gameName == "Title")
    #expect(model.gameMetadata.event == "Event")
    #expect(model.gameMetadata.date == "2026-05-25")
    #expect(model.gameMetadata.blackPlayerName == "Black")
    #expect(model.gameMetadata.whitePlayerName == "White")
    #expect(model.gameMetadata.komi == "6.5")
    #expect(model.gameMetadata.result == "B+R")
    #expect(model.game.board[BoardPoint(x: 4, y: 4)] == .black)
    #expect(model.documentError == nil)
}

@MainActor
@Test
func loadingSGFTextExposesCurrentNodeComments() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())

    model.loadSGFText("(;GM[1]FF[4]SZ[9]C[Root note];B[ee]C[Black note];W[ef]C[White note])")

    #expect(model.game.rootComment == "Root note")
    #expect(model.currentNodeComment == "White note")

    model.previousMove()

    #expect(model.currentNodeComment == "Black note")

    model.goToFirstMove()

    #expect(model.currentNodeComment == "Root note")
}

@MainActor
@Test
func editingCurrentNodeCommentUpdatesExportWithoutInvalidatingAnalysis() async throws {
    let candidatePoint = BoardPoint(x: 3, y: 3)
    let model = GokanAppModel(engine: ScriptedAnalysisEngine(snapshots: [snapshot(with: [candidatePoint])]))
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee]C[Old note])")
    model.exportedSGFText = try model.exportSGFText()
    await model.analyze()
    let originalAnalysis = try #require(model.analysis)
    let originalDiagnostics = try #require(model.analysisDiagnostics)
    let originalPositionVersion = model.positionVersion
    let originalAnalysisRequestVersion = model.analysisRequestVersion

    model.documentError = "stale error"
    model.currentNodeComment = #"New \ note ] text"#
    let exported = try model.exportSGFText()

    #expect(model.currentNodeComment == #"New \ note ] text"#)
    #expect(exported == #"(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9];B[ee]C[New \\ note \] text])"# + "\n")
    #expect(model.sgfText.isEmpty)
    #expect(model.documentError == nil)
    #expect(model.analysis == originalAnalysis)
    #expect(model.analysisDiagnostics == originalDiagnostics)
    #expect(model.selectedAnalysisCandidatePoint == candidatePoint)
    #expect(model.positionVersion == originalPositionVersion)
    #expect(model.analysisRequestVersion == originalAnalysisRequestVersion)
}

@MainActor
@Test
func navigatingMovesUpdatesCurrentNodeComment() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9]C[Root];B[ee]C[Black];W[ef]C[White])")

    #expect(model.currentNodeComment == "White")

    model.previousMove()
    #expect(model.currentNodeComment == "Black")

    model.goToFirstMove()
    #expect(model.currentNodeComment == "Root")
}

@MainActor
@Test
func newGameResetsCurrentNodeComment() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9]C[Root];B[ee]C[Black])")

    model.newGame(boardSize: BoardSize(width: 9, height: 9))

    #expect(model.currentNodeComment.isEmpty)
    #expect(model.game.rootComment.isEmpty)
}

@MainActor
@Test
func editingGameMetadataUpdatesExportWithoutInvalidatingAnalysis() async throws {
    let candidatePoint = BoardPoint(x: 3, y: 3)
    let model = GokanAppModel(engine: ScriptedAnalysisEngine(snapshots: [snapshot(with: [candidatePoint])]))
    model.loadSGFText("(;GM[1]FF[4]SZ[9]PB[Old Black];B[ee])")
    model.exportedSGFText = try model.exportSGFText()
    await model.analyze()
    let originalAnalysis = try #require(model.analysis)
    let originalDiagnostics = try #require(model.analysisDiagnostics)
    let originalPositionVersion = model.positionVersion
    let originalAnalysisRequestVersion = model.analysisRequestVersion

    model.documentError = "stale error"
    var metadata = model.gameMetadata
    metadata.blackPlayerName = "New Black"
    metadata.whitePlayerName = "White ] Player"
    metadata.komi = "6.5"
    model.gameMetadata = metadata
    let exported = try model.exportSGFText()

    #expect(model.gameMetadata.blackPlayerName == "New Black")
    #expect(exported == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9]PB[New Black]PW[White \\] Player]KM[6.5];B[ee])\n")
    #expect(model.sgfText.isEmpty)
    #expect(model.documentError == nil)
    #expect(model.analysis == originalAnalysis)
    #expect(model.analysisDiagnostics == originalDiagnostics)
    #expect(model.selectedAnalysisCandidatePoint == candidatePoint)
    #expect(model.positionVersion == originalPositionVersion)
    #expect(model.analysisRequestVersion == originalAnalysisRequestVersion)
}

@MainActor
@Test
func newGameResetsGameMetadata() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9]PB[Black]PW[White];B[ee])")

    model.newGame(boardSize: BoardSize(width: 9, height: 9))

    #expect(model.gameMetadata == .empty)
    #expect(model.game.metadata == .empty)
}

@MainActor
@Test
func loadSGFDataImportsUTF8Game() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.play(at: BoardPoint(x: 0, y: 0))

    model.loadSGFData(Data("(;GM[1]FF[4]SZ[9];B[ee];W[])".utf8))

    #expect(model.game.board.size == BoardSize(width: 9, height: 9))
    #expect(model.game.moves.count == 2)
    #expect(model.game.board[BoardPoint(x: 4, y: 4)] == .black)
    #expect(model.game.moves[1].move == .pass)
    #expect(model.documentError == nil)
}

@MainActor
@Test
func loadSGFDataRejectsInvalidEncodingAndPreservesGame() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.play(at: BoardPoint(x: 0, y: 0))
    let originalGame = model.game

    model.loadSGFData(Data([0xFF, 0xFE, 0x00]))

    #expect(model.game == originalGame)
    #expect(model.documentError == SGFFileDocumentError.unsupportedEncoding.localizedDescription)
}

@MainActor
@Test
func loadSGFFileImportsGameFromURL() throws {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "gokan-test-\(UUID().uuidString)")
        .appendingPathExtension("sgf")
    try Data("(;GM[1]FF[4]SZ[9];B[ee])".utf8).write(to: fileURL)
    defer {
        try? FileManager.default.removeItem(at: fileURL)
    }

    model.loadSGFFile(at: fileURL)

    #expect(model.game.board[BoardPoint(x: 4, y: 4)] == .black)
    #expect(model.documentError == nil)
}

@MainActor
@Test
func sampleModelCatalogImportExposesProfileAndMissingCacheStatus() throws {
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: .empty
    )
    model.engineKind = .kataGo
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "sample-9x9-metadata")

    model.loadModelCatalogData(try sampleModelCatalogData())

    let selectedProfile = try #require(model.selectedKataGoModelProfile)
    #expect(model.modelCatalog.profiles.count == 2)
    #expect(model.modelCatalogError == nil)
    #expect(selectedProfile.displayName == "Sample 9x9 Metadata Profile")
    #expect(model.kataGoModelStatus == .missingCacheRoot(profileID: "sample-9x9-metadata"))
    #expect(model.engineStatus == .kataGoIncomplete(missingFields: ["executable path", "model cache root"]))
}

@MainActor
@Test
func exportSGFDataSerializesCurrentGameAsUTF8() throws {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.newGame(boardSize: BoardSize(width: 9, height: 9))
    model.play(at: BoardPoint(x: 4, y: 4))

    let data = try model.exportSGFData()

    #expect(String(data: data, encoding: .utf8) == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9];B[ee])\n")
    #expect(model.documentError == nil)
}

@MainActor
@Test
func previousMoveUpdatesBoardAndClearsStaleAnalysis() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee];W[ef])")
    model.analysis = AnalysisSnapshot(
        candidateMoves: [CandidateMove(point: BoardPoint(x: 3, y: 3), policy: 0.5, winRate: 0.5, visits: 10)],
        scoreLead: 1,
        completedVisits: 10
    )
    let originalVersion = model.analysisRequestVersion

    model.previousMove()

    #expect(model.game.currentMoveIndex == 1)
    #expect(model.game.board[BoardPoint(x: 4, y: 4)] == .black)
    #expect(model.game.board[BoardPoint(x: 4, y: 5)] == nil)
    #expect(model.selectedPoint == BoardPoint(x: 4, y: 4))
    #expect(model.analysis == nil)
    #expect(model.analysisRequestVersion == originalVersion + 1)
}

@MainActor
@Test
func nextMoveRestoresReviewedBoard() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee];W[ef])")
    model.previousMove()

    model.nextMove()

    #expect(model.game.currentMoveIndex == 2)
    #expect(model.game.board[BoardPoint(x: 4, y: 5)] == .white)
    #expect(model.selectedPoint == BoardPoint(x: 4, y: 5))
}

@MainActor
@Test
func reviewNavigationAtBoundariesDoesNotRetriggerAnalysis() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    let originalVersion = model.analysisRequestVersion

    model.previousMove()
    model.goToFirstMove()
    model.nextMove()
    model.goToLastMove()

    #expect(model.game.currentMoveIndex == 0)
    #expect(model.analysisRequestVersion == originalVersion)
}

@MainActor
@Test
func analysisRequestUsesReviewedMovePrefix() async {
    let engine = RecordingAnalysisEngine()
    let model = GokanAppModel(engine: engine)
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee];W[ef])")
    model.previousMove()

    await model.analyze()

    #expect(engine.lastRequest?.moves.count == 1)
    #expect(engine.lastRequest?.board[BoardPoint(x: 4, y: 4)] == .black)
    #expect(engine.lastRequest?.board[BoardPoint(x: 4, y: 5)] == nil)
}

@MainActor
@Test
func playingFromEarlierReviewMoveCreatesSGFVariation() throws {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee];W[ef])")
    model.previousMove()

    model.play(at: BoardPoint(x: 5, y: 5))
    let sgf = try model.exportSGFText()

    #expect(model.game.moves.count == 2)
    #expect(model.game.currentMoveIndex == 2)
    #expect(model.game.board[BoardPoint(x: 4, y: 5)] == nil)
    #expect(model.game.board[BoardPoint(x: 5, y: 5)] == .white)
    #expect(model.game.rootChildren[0].children.count == 2)
    #expect(sgf == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9];B[ee](;W[ef])(;W[ff]))\n")
}

@MainActor
@Test
func loadingSGFWithVariationsExposesBranchChoices() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee](;W[ef])(;W[ff]))")

    model.previousMove()

    #expect(model.game.variationChoices.count == 2)
    #expect(model.game.variationChoices[0].isSelected)
    #expect(model.game.variationChoices[1].move.move == .play(BoardPoint(x: 5, y: 5)))
}

@MainActor
@Test
func selectingAlternateVariationUpdatesBoard() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee](;W[ef])(;W[ff]))")
    model.previousMove()

    model.selectVariation(at: 1)

    #expect(model.game.currentMoveIndex == 2)
    #expect(model.game.board[BoardPoint(x: 4, y: 5)] == nil)
    #expect(model.game.board[BoardPoint(x: 5, y: 5)] == .white)
    #expect(model.selectedPoint == BoardPoint(x: 5, y: 5))
}

@MainActor
@Test
func jumpToCurrentMoveDoesNotRetriggerAnalysis() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee])")
    let originalVersion = model.analysisRequestVersion

    model.goToMove(model.game.currentMoveIndex)

    #expect(model.game.currentMoveIndex == 1)
    #expect(model.analysisRequestVersion == originalVersion)
}

@MainActor
@Test
func jumpToMoveUpdatesReviewedBoardAndSelectedPoint() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee];W[ef])")
    model.analysis = AnalysisSnapshot(
        candidateMoves: [CandidateMove(point: BoardPoint(x: 3, y: 3), policy: 0.5, winRate: 0.5, visits: 10)],
        scoreLead: 1,
        completedVisits: 10
    )
    let originalVersion = model.analysisRequestVersion

    model.goToMove(1)

    #expect(model.game.currentMoveIndex == 1)
    #expect(model.game.board[BoardPoint(x: 4, y: 4)] == .black)
    #expect(model.game.board[BoardPoint(x: 4, y: 5)] == nil)
    #expect(model.selectedPoint == BoardPoint(x: 4, y: 4))
    #expect(model.analysis == nil)
    #expect(model.analysisRequestVersion == originalVersion + 1)
}

@MainActor
@Test
func jumpToRootClearsSelectedPointAndPreservesDocumentText() throws {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee];W[ef])")
    model.exportedSGFText = try model.exportSGFText()
    let originalSGFText = model.sgfText
    let originalExportText = model.exportedSGFText

    model.goToMove(0)

    #expect(model.game.currentMoveIndex == 0)
    #expect(model.game.board.occupiedPoints.isEmpty)
    #expect(model.selectedPoint == nil)
    #expect(model.sgfText == originalSGFText)
    #expect(model.exportedSGFText == originalExportText)
}

@MainActor
@Test
func jumpToPassMoveClearsSelectedPoint() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee];W[])")
    model.goToMove(1)

    model.goToMove(2)

    #expect(model.game.currentMoveIndex == 2)
    #expect(model.selectedPoint == nil)
}

@MainActor
@Test
func jumpToMoveUsesSelectedVariationLine() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee](;W[ef])(;W[ff]))")
    model.previousMove()
    model.selectVariation(at: 1)

    model.goToMove(1)
    model.goToMove(2)

    #expect(model.game.moves[1].move == .play(BoardPoint(x: 5, y: 5)))
    #expect(model.game.board[BoardPoint(x: 4, y: 5)] == nil)
    #expect(model.game.board[BoardPoint(x: 5, y: 5)] == .white)
    #expect(model.selectedPoint == BoardPoint(x: 5, y: 5))
}

@MainActor
@Test
func analysisRequestUsesDirectJumpPrefix() async {
    let engine = RecordingAnalysisEngine()
    let model = GokanAppModel(engine: engine)
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee];W[ef])")
    model.goToMove(1)

    await model.analyze()

    #expect(engine.lastRequest?.moves.count == 1)
    #expect(engine.lastRequest?.board[BoardPoint(x: 4, y: 4)] == .black)
    #expect(engine.lastRequest?.board[BoardPoint(x: 4, y: 5)] == nil)
}

@MainActor
@Test
func analysisRequestUsesConfiguredVisits() async throws {
    let engine = RecordingAnalysisEngine()
    let model = GokanAppModel(engine: engine)

    model.analysisVisits = 1_200
    await model.analyze()

    #expect(engine.lastRequest?.visits == 1_200)
    let diagnostics = try #require(model.analysisDiagnostics)
    #expect(diagnostics.requestedVisits == 1_200)
}

@MainActor
@Test
func successfulAnalysisRecordsDiagnostics() async throws {
    let finalPoint = BoardPoint(x: 4, y: 4)
    let engine = ScriptedAnalysisEngine(
        snapshots: [
            AnalysisSnapshot(
                candidateMoves: [
                    CandidateMove(point: BoardPoint(x: 3, y: 3), policy: 0.4, winRate: 0.51, visits: 7),
                ],
                scoreLead: -0.5,
                completedVisits: 10
            ),
            AnalysisSnapshot(
                candidateMoves: [
                    CandidateMove(point: finalPoint, policy: 0.5, winRate: 0.58, visits: 80),
                    CandidateMove(point: BoardPoint(x: 5, y: 5), policy: 0.2, winRate: 0.54, visits: 30),
                ],
                scoreLead: 2.25,
                completedVisits: 100
            ),
        ]
    )
    let model = GokanAppModel(engine: engine)

    await model.analyze()

    let diagnostics = try #require(model.analysisDiagnostics)
    #expect(diagnostics.outcome == .succeeded)
    #expect(diagnostics.engineKind == .mock)
    #expect(diagnostics.boardSize == model.game.board.size)
    #expect(diagnostics.moveIndex == model.game.currentMoveIndex)
    #expect(diagnostics.moveCount == model.game.moves.count)
    #expect(diagnostics.requestedVisits == 400)
    #expect(diagnostics.snapshotsReceived == 2)
    #expect(diagnostics.completedVisits == 100)
    #expect(diagnostics.candidateCount == 2)
    #expect(diagnostics.scoreLead == 2.25)
    #expect(diagnostics.finishedAt != nil)
    #expect(try #require(diagnostics.durationSeconds) >= 0)
    #expect(model.analysis?.candidateMoves.first?.point == finalPoint)
}

@MainActor
@Test
func staleAnalysisDoesNotOverwriteNewerPosition() async throws {
    let engine = ControlledAnalysisEngine()
    let model = GokanAppModel(engine: engine)

    let analysisTask = Task {
        await model.analyze()
    }

    while engine.hasContinuation == false {
        try await Task.sleep(nanoseconds: 1_000_000)
    }

    #expect(model.analysisDiagnostics?.outcome == .running)
    model.play(at: BoardPoint(x: 0, y: 0))
    engine.yield(
        AnalysisSnapshot(
            candidateMoves: [CandidateMove(point: BoardPoint(x: 4, y: 4), policy: 0.5, winRate: 0.5, visits: 10)],
            scoreLead: 1,
            completedVisits: 10
        )
    )
    engine.finish()
    await analysisTask.value

    #expect(model.analysis == nil)
    #expect(model.analysisDiagnostics == nil)
}

@MainActor
@Test
func cancelledAnalysisMarksDiagnosticsCancelled() async throws {
    let engine = ControlledAnalysisEngine()
    let model = GokanAppModel(engine: engine)

    let analysisTask = Task {
        await model.analyze()
    }

    while engine.hasContinuation == false {
        try await Task.sleep(nanoseconds: 1_000_000)
    }

    #expect(model.analysisDiagnostics?.outcome == .running)
    analysisTask.cancel()
    engine.finish()
    await analysisTask.value

    let diagnostics = try #require(model.analysisDiagnostics)
    #expect(diagnostics.outcome == .cancelled)
    #expect(diagnostics.snapshotsReceived == 0)
    #expect(diagnostics.finishedAt != nil)
    #expect(model.analysisError == nil)
}

@MainActor
@Test
func analysisSnapshotSelectsTopCandidateByDefault() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    let first = BoardPoint(x: 3, y: 3)
    let second = BoardPoint(x: 4, y: 4)

    model.analysis = snapshot(with: [first, second])

    #expect(model.selectedAnalysisCandidatePoint == first)
    #expect(model.selectedAnalysisCandidate?.point == first)
    #expect(model.canPlaySelectedAnalysisCandidate)
}

@MainActor
@Test
func selectAnalysisCandidateUpdatesSelectedPoint() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    let first = BoardPoint(x: 3, y: 3)
    let second = BoardPoint(x: 4, y: 4)
    model.analysis = snapshot(with: [first, second])

    model.selectAnalysisCandidate(at: second)

    #expect(model.selectedAnalysisCandidatePoint == second)
    #expect(model.selectedAnalysisCandidate?.point == second)
}

@MainActor
@Test
func selectAnalysisCandidateIgnoresPointOutsideCurrentAnalysis() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    let candidatePoint = BoardPoint(x: 3, y: 3)
    let unrelatedPoint = BoardPoint(x: 8, y: 8)
    model.analysis = snapshot(with: [candidatePoint])

    model.selectAnalysisCandidate(at: unrelatedPoint)

    #expect(model.selectedAnalysisCandidatePoint == candidatePoint)
}

@MainActor
@Test
func selectedAnalysisCandidateIsPreservedAcrossSnapshotsWhenStillPresent() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    let first = BoardPoint(x: 3, y: 3)
    let selected = BoardPoint(x: 4, y: 4)
    let replacementTop = BoardPoint(x: 5, y: 5)
    model.analysis = snapshot(with: [first, selected])
    model.selectAnalysisCandidate(at: selected)

    model.analysis = snapshot(with: [replacementTop, selected])

    #expect(model.selectedAnalysisCandidatePoint == selected)
    #expect(model.selectedAnalysisCandidate?.point == selected)
}

@MainActor
@Test
func selectedAnalysisCandidateFallsBackToTopWhenMissingFromNewSnapshot() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    let first = BoardPoint(x: 3, y: 3)
    let selected = BoardPoint(x: 4, y: 4)
    let replacementTop = BoardPoint(x: 5, y: 5)
    model.analysis = snapshot(with: [first, selected])
    model.selectAnalysisCandidate(at: selected)

    model.analysis = snapshot(with: [replacementTop, first])

    #expect(model.selectedAnalysisCandidatePoint == replacementTop)
    #expect(model.selectedAnalysisCandidate?.point == replacementTop)
}

@MainActor
@Test
func emptyAnalysisSnapshotClearsSelectedCandidate() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.analysis = snapshot(with: [BoardPoint(x: 3, y: 3)])

    model.analysis = snapshot(with: [])

    #expect(model.selectedAnalysisCandidatePoint == nil)
    #expect(model.selectedAnalysisCandidate == nil)
    #expect(model.canPlaySelectedAnalysisCandidate == false)
}

@MainActor
@Test
func positionChangeClearsSelectedAnalysisCandidate() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.analysis = snapshot(with: [BoardPoint(x: 3, y: 3)])

    model.play(at: BoardPoint(x: 4, y: 4))

    #expect(model.analysis == nil)
    #expect(model.selectedAnalysisCandidatePoint == nil)
    #expect(model.selectedAnalysisCandidate == nil)
}

@MainActor
@Test
func positionChangeClearsAnalysisDiagnostics() async {
    let model = GokanAppModel(engine: ScriptedAnalysisEngine(snapshots: [snapshot(with: [BoardPoint(x: 3, y: 3)])]))
    await model.analyze()
    #expect(model.analysisDiagnostics != nil)

    model.play(at: BoardPoint(x: 4, y: 4))

    #expect(model.analysisDiagnostics == nil)
}

@MainActor
@Test
func engineSettingChangeClearsSelectedAnalysisCandidate() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.analysis = snapshot(with: [BoardPoint(x: 3, y: 3)])

    model.engineKind = .kataGo

    #expect(model.analysis == nil)
    #expect(model.selectedAnalysisCandidatePoint == nil)
    #expect(model.selectedAnalysisCandidate == nil)
}

@MainActor
@Test
func engineSettingChangeClearsAnalysisDiagnostics() async {
    let model = GokanAppModel(engine: ScriptedAnalysisEngine(snapshots: [snapshot(with: [BoardPoint(x: 3, y: 3)])]))
    await model.analyze()
    #expect(model.analysisDiagnostics != nil)

    model.engineKind = .kataGo

    #expect(model.analysisDiagnostics == nil)
}

@MainActor
@Test
func analysisVisitsChangeClearsStaleAnalysisAndIncrementsRequestVersion() async {
    let model = GokanAppModel(engine: ScriptedAnalysisEngine(snapshots: [snapshot(with: [BoardPoint(x: 4, y: 4)])]))
    await model.analyze()
    model.analysisError = "old error"
    let originalVersion = model.analysisRequestVersion

    #expect(model.analysis != nil)
    #expect(model.analysisDiagnostics != nil)

    model.analysisVisits = 1_000

    #expect(model.analysis == nil)
    #expect(model.analysisError == nil)
    #expect(model.analysisDiagnostics == nil)
    #expect(model.analysisRequestVersion == originalVersion + 1)
}

@MainActor
@Test
func playSelectedAnalysisCandidateUsesExistingMovePipeline() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    let candidatePoint = BoardPoint(x: 3, y: 3)
    let originalVersion = model.analysisRequestVersion
    model.analysis = snapshot(with: [candidatePoint])

    model.playSelectedAnalysisCandidate()

    #expect(model.game.moves.count == 1)
    #expect(model.game.board[candidatePoint] == .black)
    #expect(model.selectedPoint == candidatePoint)
    #expect(model.analysis == nil)
    #expect(model.selectedAnalysisCandidatePoint == nil)
    #expect(model.analysisRequestVersion == originalVersion + 1)
}

@MainActor
@Test
func illegalSelectedAnalysisCandidateIsNotPlayable() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    let suicidePoint = BoardPoint(x: 2, y: 2)
    model.newGame(boardSize: BoardSize(width: 5, height: 5))
    model.play(at: BoardPoint(x: 0, y: 0))
    model.play(at: BoardPoint(x: 1, y: 2))
    model.play(at: BoardPoint(x: 4, y: 4))
    model.play(at: BoardPoint(x: 2, y: 1))
    model.play(at: BoardPoint(x: 0, y: 4))
    model.play(at: BoardPoint(x: 3, y: 2))
    model.play(at: BoardPoint(x: 4, y: 0))
    model.play(at: BoardPoint(x: 2, y: 3))
    model.analysis = snapshot(with: [suicidePoint])
    let originalMoveCount = model.game.moves.count

    model.playSelectedAnalysisCandidate()

    #expect(model.canPlaySelectedAnalysisCandidate == false)
    #expect(model.game.moves.count == originalMoveCount)
    #expect(model.game.board[suicidePoint] == nil)
    #expect(model.analysis != nil)
    #expect(model.selectedAnalysisCandidatePoint == suicidePoint)
}

@MainActor
@Test
func playSelectedAnalysisCandidateCreatesVariationFromReviewedPosition() throws {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    let alternatePoint = BoardPoint(x: 5, y: 5)
    model.loadSGFText("(;GM[1]FF[4]SZ[9];B[ee];W[ef])")
    model.previousMove()
    model.analysis = snapshot(with: [alternatePoint])

    model.playSelectedAnalysisCandidate()
    let sgf = try model.exportSGFText()

    #expect(model.game.board[BoardPoint(x: 4, y: 5)] == nil)
    #expect(model.game.board[alternatePoint] == .white)
    #expect(model.game.rootChildren[0].children.count == 2)
    #expect(sgf == "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[9];B[ee](;W[ef])(;W[ff]))\n")
}

@MainActor
@Test
func modelDefaultsToMockEngineStatus() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())

    #expect(model.engineKind == .mock)
    #expect(model.engineStatus == .mock)
}

@MainActor
@Test
func selectingKataGoWithMissingPathsReportsIncompleteStatus() async {
    let probe = EngineFactoryProbe()
    let model = GokanAppModel(
        engineFactory: probe.makeEngine(selection:),
        supportsKataGoSubprocess: true
    )

    model.engineKind = .kataGo
    await model.analyze()

    #expect(model.engineStatus == .kataGoIncomplete(missingFields: ["executable path", "model path", "config path"]))
    #expect(model.analysisError == EngineStatus.kataGoIncomplete(missingFields: ["executable path", "model path", "config path"]).message)
    #expect(probe.callCount == 0)
    #expect(
        model.analysisDiagnostics?.outcome
            == .failed(message: EngineStatus.kataGoIncomplete(missingFields: ["executable path", "model path", "config path"]).message)
    )
    #expect(model.analysisDiagnostics?.engineKind == .kataGo)
    #expect(model.analysisDiagnostics?.snapshotsReceived == 0)
}

@MainActor
@Test
func selectingKataGoWhenSubprocessUnsupportedReportsUnavailableStatus() async {
    let probe = EngineFactoryProbe()
    let model = GokanAppModel(
        engineFactory: probe.makeEngine(selection:),
        supportsKataGoSubprocess: false
    )

    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(
        executablePath: "/usr/local/bin/katago",
        modelPath: "/models/model.bin.gz",
        configPath: "/configs/analysis.cfg"
    )
    await model.analyze()

    #expect(model.engineStatus == .kataGoUnsupported)
    #expect(model.analysisError == EngineStatus.kataGoUnsupported.message)
    #expect(probe.callCount == 0)
}

@MainActor
@Test
func configuredKataGoSelectionIsPassedToEngineFactory() throws {
    let temp = try TemporaryDirectory()
    let files = try makeKataGoFileFixture(in: temp)
    let probe = EngineFactoryProbe()
    let model = GokanAppModel(
        engineFactory: probe.makeEngine(selection:),
        supportsKataGoSubprocess: true
    )

    model.engineKind = .kataGo
    model.kataGoSettings = files.settings
    _ = try model.makeAnalysisEngine()

    #expect(model.engineStatus == .kataGoConfigured)
    #expect(probe.callCount == 1)
    #expect(
        probe.lastSelection == AnalysisEngineSelection(
            kind: .kataGo,
            kataGoSettings: files.settings,
            resolvedKataGoConfiguration: KataGoEngineConfiguration(
                executableURL: files.executableURL,
                modelURL: files.modelURL,
                configURL: files.configURL
            )
        )
    )
}

@MainActor
@Test
func missingKataGoExecutableBlocksEngineFactory() async throws {
    let temp = try TemporaryDirectory()
    let files = try makeKataGoFileFixture(in: temp, createExecutable: false)
    let probe = EngineFactoryProbe()
    let model = GokanAppModel(
        engineFactory: probe.makeEngine(selection:),
        supportsKataGoSubprocess: true
    )

    model.engineKind = .kataGo
    model.kataGoSettings = files.settings
    await model.analyze()

    let expectedStatus = EngineStatus.kataGoMissingExecutable(path: files.executableURL.path)
    #expect(model.engineStatus == expectedStatus)
    #expect(model.analysisError == expectedStatus.message)
    #expect(probe.callCount == 0)
    #expect(model.analysisDiagnostics?.outcome == .failed(message: expectedStatus.message))
    #expect(model.analysisDiagnostics?.engineKind == .kataGo)
    #expect(model.analysisDiagnostics?.snapshotsReceived == 0)
}

@MainActor
@Test
func makeAnalysisEngineRefreshesStaleMissingFileStatus() throws {
    let temp = try TemporaryDirectory()
    let files = try makeKataGoFileFixture(in: temp, createExecutable: false)
    let probe = EngineFactoryProbe()
    let model = GokanAppModel(
        engineFactory: probe.makeEngine(selection:),
        supportsKataGoSubprocess: true
    )

    model.engineKind = .kataGo
    model.kataGoSettings = files.settings
    #expect(model.engineStatus == .kataGoMissingExecutable(path: files.executableURL.path))

    try writeData("katago", to: files.executableURL)
    _ = try model.makeAnalysisEngine()

    #expect(model.engineStatus == .kataGoConfigured)
    #expect(probe.callCount == 1)
}

@MainActor
@Test
func missingKataGoModelAndConfigSurfaceSpecificStatuses() throws {
    let temp = try TemporaryDirectory()
    let missingModelFiles = try makeKataGoFileFixture(in: temp, createModel: false)
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true
    )

    model.engineKind = .kataGo
    model.kataGoSettings = missingModelFiles.settings
    #expect(model.engineStatus == .kataGoMissingModel(path: missingModelFiles.modelURL.path))

    let missingConfigFiles = try makeKataGoFileFixture(in: temp, prefix: "missing-config", createConfig: false)
    model.kataGoSettings = missingConfigFiles.settings
    #expect(model.engineStatus == .kataGoMissingConfig(path: missingConfigFiles.configURL.path))
}

@MainActor
@Test
func kataGoModelSettingsPersistAcrossModelInstances() throws {
    let defaults = isolatedDefaults()
    let catalog = try modelCatalog()
    let firstModel = GokanAppModel(
        engine: SilentAnalysisEngine(),
        settingsDefaults: defaults.userDefaults,
        supportsKataGoSubprocess: true,
        modelCatalog: catalog
    )

    firstModel.engineKind = .kataGo
    firstModel.kataGoModelSettings = KataGoModelSettings(
        selectedProfileID: "tiny-dev",
        cacheRootPath: "/tmp/gokan-models"
    )
    let restoredModel = GokanAppModel(
        engine: SilentAnalysisEngine(),
        settingsDefaults: defaults.userDefaults,
        supportsKataGoSubprocess: true,
        modelCatalog: catalog
    )

    #expect(restoredModel.kataGoModelSettings.selectedProfileID == "tiny-dev")
    #expect(restoredModel.kataGoModelSettings.cacheRootPath == "/tmp/gokan-models")
}

@MainActor
@Test
func loadModelCatalogDataReplacesEmptyCatalog() throws {
    let model = GokanAppModel(engine: SilentAnalysisEngine(), modelCatalog: .empty)

    model.loadModelCatalogData(try modelCatalog().encode())

    #expect(model.modelCatalog.profile(id: "tiny-dev")?.displayName == "Tiny Dev Model")
    #expect(model.modelCatalogError == nil)
}

@MainActor
@Test
func invalidModelCatalogDataPreservesCurrentCatalogAndReportsError() throws {
    let catalog = try modelCatalog()
    let model = GokanAppModel(engine: SilentAnalysisEngine(), modelCatalog: catalog)

    model.loadModelCatalogData(Data("not json".utf8))

    #expect(model.modelCatalog == catalog)
    #expect(model.modelCatalogError?.isEmpty == false)
}

@MainActor
@Test
func importedModelCatalogPersistsAcrossModelInstances() throws {
    let defaults = isolatedDefaults()
    let firstModel = GokanAppModel(
        engine: SilentAnalysisEngine(),
        settingsDefaults: defaults.userDefaults,
        modelCatalog: .empty
    )

    firstModel.loadModelCatalogData(try modelCatalog().encode())
    let restoredModel = GokanAppModel(
        engine: SilentAnalysisEngine(),
        settingsDefaults: defaults.userDefaults,
        modelCatalog: .empty
    )

    #expect(restoredModel.modelCatalog.profile(id: "tiny-dev")?.displayName == "Tiny Dev Model")
    #expect(restoredModel.modelCatalogError == nil)
}

@MainActor
@Test
func invalidPersistedModelCatalogFallsBackAndClearsPersistedData() {
    let defaults = isolatedDefaults()
    defaults.userDefaults.set(Data("not json".utf8), forKey: "Gokan.modelCatalog.data")

    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        settingsDefaults: defaults.userDefaults,
        modelCatalog: .empty
    )

    #expect(model.modelCatalog.profiles.isEmpty)
    #expect(model.modelCatalogError?.isEmpty == false)
    #expect(defaults.userDefaults.data(forKey: "Gokan.modelCatalog.data") == nil)
}

@MainActor
@Test
func clearingModelCatalogRemovesPersistedMetadataAndRefreshesStatus() throws {
    let defaults = isolatedDefaults()
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        settingsDefaults: defaults.userDefaults,
        supportsKataGoSubprocess: true,
        modelCatalog: .empty
    )

    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(executablePath: "/usr/local/bin/katago")
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: "/tmp/gokan-models")
    model.loadModelCatalogData(try modelCatalog().encode())
    model.clearModelCatalog()

    let restoredModel = GokanAppModel(
        engine: SilentAnalysisEngine(),
        settingsDefaults: defaults.userDefaults,
        supportsKataGoSubprocess: true,
        modelCatalog: .empty
    )
    #expect(model.modelCatalog.profiles.isEmpty)
    #expect(model.kataGoModelStatus == .profileUnavailable(profileID: "tiny-dev"))
    #expect(defaults.userDefaults.data(forKey: "Gokan.modelCatalog.data") == nil)
    #expect(restoredModel.modelCatalog.profiles.isEmpty)
}

@MainActor
@Test
func loadingModelCatalogEnablesSelectedProfileResolution() throws {
    let temp = try TemporaryDirectory()
    let catalog = try modelCatalog()
    let profile = try #require(catalog.profile(id: "tiny-dev"))
    let cache = GokanModelCache(rootURL: temp.url)
    let executableURL = temp.url.appending(path: "bin/katago")
    try writeData("katago", to: executableURL)
    try writeData("hello", to: cache.modelURL(for: profile))
    try writeData("config", to: try #require(cache.configURL(for: profile)))
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: .empty
    )

    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(executablePath: executableURL.path)
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: temp.url.path)
    model.loadModelCatalogData(try catalog.encode())

    #expect(model.engineStatus == .kataGoConfigured)
    #expect(
        model.kataGoModelStatus
            == .profileReady(
                profileID: "tiny-dev",
                displayName: "Tiny Dev Model",
                modelPath: cache.modelURL(for: profile).path,
                configPath: cache.configURL(for: profile)?.path
            )
    )
}

@MainActor
@Test
func loadingModelCatalogWhileMockDoesNotRetriggerAnalysis() throws {
    let model = GokanAppModel(engine: SilentAnalysisEngine(), modelCatalog: .empty)
    let originalVersion = model.analysisRequestVersion

    model.loadModelCatalogData(try modelCatalog().encode())

    #expect(model.engineKind == .mock)
    #expect(model.analysisRequestVersion == originalVersion)
}

@MainActor
@Test
func loadingModelCatalogWhileKataGoInvalidatesAnalysisWhenResolutionChanges() throws {
    let temp = try TemporaryDirectory()
    let initialCatalog = try modelCatalog()
    let initialProfile = try #require(initialCatalog.profile(id: "tiny-dev"))
    let cache = GokanModelCache(rootURL: temp.url)
    let executableURL = temp.url.appending(path: "bin/katago")
    try writeData("katago", to: executableURL)
    try writeData("hello", to: cache.modelURL(for: initialProfile))
    try writeData("config", to: try #require(cache.configURL(for: initialProfile)))
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: initialCatalog
    )
    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(executablePath: executableURL.path)
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: temp.url.path)
    model.analysis = snapshot(with: [BoardPoint(x: 3, y: 3)])
    let originalVersion = model.analysisRequestVersion

    model.loadModelCatalogData(try alternateModelCatalog().encode())

    #expect(model.analysis == nil)
    #expect(model.analysisRequestVersion == originalVersion + 1)
}

@MainActor
@Test
func checksumVerificationResultIsDiscardedWhenCatalogChanges() async throws {
    let temp = try TemporaryDirectory()
    let catalog = try modelCatalog()
    let profile = try #require(catalog.profile(id: "tiny-dev"))
    let cache = GokanModelCache(rootURL: temp.url)
    let executableURL = temp.url.appending(path: "bin/katago")
    try writeData("katago", to: executableURL)
    let payload = Data(repeating: 0x68, count: 32 * 1024 * 1024)
    try FileManager.default.createDirectory(at: cache.modelURL(for: profile).deletingLastPathComponent(), withIntermediateDirectories: true)
    try payload.write(to: cache.modelURL(for: profile))
    try writeData("config", to: try #require(cache.configURL(for: profile)))
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: catalog
    )
    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(executablePath: executableURL.path)
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: temp.url.path)

    let verification = Task {
        await model.verifySelectedKataGoModelChecksum()
    }
    await Task.yield()
    model.loadModelCatalogData(try alternateModelCatalog().encode())
    await verification.value

    #expect(model.kataGoModelStatus == .missingCachedModel(profileID: "tiny-dev", path: temp.url.appending(path: "models").appending(path: "alternate.bin.gz").path))
}

@MainActor
@Test
func selectedKataGoModelProfileReflectsModelSettings() throws {
    let catalog = try modelCatalog()
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: catalog
    )

    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: "")

    #expect(model.selectedKataGoModelProfile?.id == "tiny-dev")
}

@MainActor
@Test
func profileAndCacheRootEnableChecksumVerificationAction() throws {
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: try modelCatalog()
    )

    model.engineKind = .kataGo
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: "/tmp/gokan-models")

    #expect(model.isUsingManualKataGoModelPath == false)
    #expect(model.canVerifySelectedKataGoModelChecksum)
}

@MainActor
@Test
func cachedModelProfileDerivesKataGoConfiguration() throws {
    let temp = try TemporaryDirectory()
    let catalog = try modelCatalog()
    let cache = GokanModelCache(rootURL: temp.url)
    let profile = try #require(catalog.profile(id: "tiny-dev"))
    let executableURL = temp.url.appending(path: "bin/katago")
    try writeData("katago", to: executableURL)
    try writeData("hello", to: cache.modelURL(for: profile))
    try writeData("config", to: try #require(cache.configURL(for: profile)))
    let probe = EngineFactoryProbe()
    let model = GokanAppModel(
        engineFactory: probe.makeEngine(selection:),
        supportsKataGoSubprocess: true,
        modelCatalog: catalog
    )

    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(executablePath: executableURL.path)
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: temp.url.path)
    _ = try model.makeAnalysisEngine()

    #expect(model.engineStatus == .kataGoConfigured)
    #expect(
        model.kataGoModelStatus
            == .profileReady(
                profileID: "tiny-dev",
                displayName: "Tiny Dev Model",
                modelPath: cache.modelURL(for: profile).path,
                configPath: cache.configURL(for: profile)?.path
            )
    )
    #expect(
        probe.lastSelection?.resolvedKataGoConfiguration
            == KataGoEngineConfiguration(
                executableURL: executableURL,
                modelURL: cache.modelURL(for: profile),
                configURL: try #require(cache.configURL(for: profile))
            )
    )
}

@MainActor
@Test
func missingCachedModelReportsIncompleteStatus() throws {
    let temp = try TemporaryDirectory()
    let catalog = try modelCatalog()
    let profile = try #require(catalog.profile(id: "tiny-dev"))
    let cache = GokanModelCache(rootURL: temp.url)
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: catalog
    )

    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(executablePath: "/usr/local/bin/katago")
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: temp.url.path)

    #expect(model.engineStatus == .kataGoIncomplete(missingFields: ["cached model file"]))
    #expect(model.kataGoModelStatus == .missingCachedModel(profileID: "tiny-dev", path: cache.modelURL(for: profile).path))
}

@MainActor
@Test
func missingCachedConfigReportsIncompleteStatus() throws {
    let temp = try TemporaryDirectory()
    let catalog = try modelCatalog()
    let profile = try #require(catalog.profile(id: "tiny-dev"))
    let cache = GokanModelCache(rootURL: temp.url)
    try writeData("hello", to: cache.modelURL(for: profile))
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: catalog
    )

    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(executablePath: "/usr/local/bin/katago")
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: temp.url.path)

    #expect(model.engineStatus == .kataGoIncomplete(missingFields: ["cached config file"]))
    #expect(model.kataGoModelStatus == .missingCachedConfig(profileID: "tiny-dev", path: try #require(cache.configURL(for: profile)).path))
}

@MainActor
@Test
func modelProfileWithoutDefaultConfigReportsManualConfigRequired() throws {
    let temp = try TemporaryDirectory()
    let catalog = try modelOnlyCatalog()
    let cache = GokanModelCache(rootURL: temp.url)
    let profile = try #require(catalog.profile(id: "model-only"))
    try writeData("hello", to: cache.modelURL(for: profile))
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: catalog
    )

    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(executablePath: "/usr/local/bin/katago")
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "model-only", cacheRootPath: temp.url.path)

    #expect(model.engineStatus == .kataGoIncomplete(missingFields: ["config path"]))
    #expect(model.kataGoModelStatus == .missingConfigPath)
}

@MainActor
@Test
func rawModelPathTakesPrecedenceOverSelectedProfile() throws {
    let temp = try TemporaryDirectory()
    let files = try makeKataGoFileFixture(in: temp)
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: (try? modelCatalog()) ?? .empty
    )

    model.engineKind = .kataGo
    model.kataGoSettings = files.settings
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: "/missing/cache")

    #expect(model.engineStatus == .kataGoConfigured)
    #expect(model.kataGoModelStatus == .manualPath(path: files.modelURL.path))
    #expect(model.isUsingManualKataGoModelPath)
    #expect(model.canVerifySelectedKataGoModelChecksum == false)
}

@MainActor
@Test
func rawModelPathWithoutConfigReportsConfigPathMissing() {
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: (try? modelCatalog()) ?? .empty
    )

    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(
        executablePath: "/usr/local/bin/katago",
        modelPath: "/manual/model.bin.gz"
    )
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: "/missing/cache")

    #expect(model.engineStatus == .kataGoIncomplete(missingFields: ["config path"]))
    #expect(model.kataGoModelStatus == .missingConfigPath)
    #expect(model.isUsingManualKataGoModelPath)
    #expect(model.canVerifySelectedKataGoModelChecksum == false)
}

@MainActor
@Test
func unknownModelProfileReportsUnavailableStatus() {
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: (try? modelCatalog()) ?? .empty
    )

    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(executablePath: "/usr/local/bin/katago")
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "future-profile", cacheRootPath: "/tmp/gokan-models")

    #expect(model.engineStatus == .kataGoIncomplete(missingFields: ["model profile"]))
    #expect(model.kataGoModelStatus == .profileUnavailable(profileID: "future-profile"))
    #expect(model.selectedKataGoModelProfile == nil)
    #expect(model.canVerifySelectedKataGoModelChecksum == false)
}

@MainActor
@Test
func successfulChecksumVerificationClearsPreviousMismatchEngineError() async throws {
    let temp = try TemporaryDirectory()
    let catalog = try modelCatalog()
    let cache = GokanModelCache(rootURL: temp.url)
    let profile = try #require(catalog.profile(id: "tiny-dev"))
    let executableURL = temp.url.appending(path: "bin/katago")
    try writeData("katago", to: executableURL)
    try writeData("wrong", to: cache.modelURL(for: profile))
    try writeData("config", to: try #require(cache.configURL(for: profile)))
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: catalog
    )

    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(executablePath: executableURL.path)
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: temp.url.path)
    await model.verifySelectedKataGoModelChecksum()

    #expect(
        model.kataGoModelStatus
            == .checksumMismatch(
                profileID: "tiny-dev",
                expected: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
                actual: "8810ad581e59f2bc3928b261707a71308f7e139eb04820366dc4d5c18d980225"
            )
    )
    #expect(model.engineStatus == .error(model.kataGoModelStatus.message))

    try writeData("hello", to: cache.modelURL(for: profile))
    await model.verifySelectedKataGoModelChecksum()

    #expect(
        model.kataGoModelStatus
            == .checksumVerified(profileID: "tiny-dev", sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    )
    #expect(model.engineStatus == .kataGoConfigured)
}

@MainActor
@Test
func checksumVerificationDoesNotSetEngineErrorWhenCurrentEngineIsMock() async throws {
    let temp = try TemporaryDirectory()
    let catalog = try modelCatalog()
    let cache = GokanModelCache(rootURL: temp.url)
    let profile = try #require(catalog.profile(id: "tiny-dev"))
    try writeData("wrong", to: cache.modelURL(for: profile))
    try writeData("config", to: try #require(cache.configURL(for: profile)))
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: catalog
    )

    model.kataGoSettings = KataGoPathSettings(executablePath: "/usr/local/bin/katago")
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: temp.url.path)
    await model.verifySelectedKataGoModelChecksum()

    #expect(model.engineKind == .mock)
    #expect(model.engineStatus == .mock)
}

@MainActor
@Test
func verifySelectedKataGoModelChecksumUpdatesStatus() async throws {
    let temp = try TemporaryDirectory()
    let catalog = try modelCatalog()
    let cache = GokanModelCache(rootURL: temp.url)
    let profile = try #require(catalog.profile(id: "tiny-dev"))
    try writeData("hello", to: cache.modelURL(for: profile))
    try writeData("config", to: try #require(cache.configURL(for: profile)))
    let model = GokanAppModel(
        engine: SilentAnalysisEngine(),
        supportsKataGoSubprocess: true,
        modelCatalog: catalog
    )

    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(executablePath: "/usr/local/bin/katago")
    model.kataGoModelSettings = KataGoModelSettings(selectedProfileID: "tiny-dev", cacheRootPath: temp.url.path)
    await model.verifySelectedKataGoModelChecksum()

    #expect(
        model.kataGoModelStatus
            == .checksumVerified(profileID: "tiny-dev", sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    )
}

@MainActor
@Test
func engineSettingChangesClearStaleAnalysisAndRetriggerAnalysis() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())
    model.analysis = AnalysisSnapshot(
        candidateMoves: [CandidateMove(point: BoardPoint(x: 4, y: 4), policy: 0.5, winRate: 0.5, visits: 10)],
        scoreLead: 1,
        completedVisits: 10
    )
    model.analysisError = "old error"
    let originalVersion = model.analysisRequestVersion

    model.engineKind = .kataGo

    #expect(model.analysis == nil)
    #expect(model.analysisError == nil)
    #expect(model.analysisRequestVersion == originalVersion + 1)
}

@MainActor
@Test
func runtimeFactoryErrorSurfacesAsAnalysisErrorAndEngineStatus() async {
    let model = GokanAppModel { _ in
        throw FactoryError.unavailable
    }

    await model.analyze()

    #expect(model.analysisError == FactoryError.unavailable.localizedDescription)
    #expect(model.engineStatus == .error(FactoryError.unavailable.localizedDescription))
    #expect(model.analysisDiagnostics?.outcome == .failed(message: FactoryError.unavailable.localizedDescription))
    #expect(model.analysisDiagnostics?.snapshotsReceived == 0)
    #expect(model.analysisDiagnostics?.durationSeconds != nil)
}

@MainActor
@Test
func engineSettingsPersistAcrossModelInstances() throws {
    let temp = try TemporaryDirectory()
    let files = try makeKataGoFileFixture(in: temp, modelName: "g170.bin.gz")
    let defaults = isolatedDefaults()
    let settings = files.settings
    let firstModel = GokanAppModel(
        engine: SilentAnalysisEngine(),
        settingsDefaults: defaults.userDefaults,
        supportsKataGoSubprocess: true
    )

    firstModel.engineKind = .kataGo
    firstModel.kataGoSettings = settings
    firstModel.analysisVisits = 1_500
    let restoredModel = GokanAppModel(
        engine: SilentAnalysisEngine(),
        settingsDefaults: defaults.userDefaults,
        supportsKataGoSubprocess: true
    )

    #expect(restoredModel.engineKind == .kataGo)
    #expect(restoredModel.kataGoSettings == settings)
    #expect(restoredModel.analysisVisits == 1_500)
    #expect(restoredModel.engineStatus == .kataGoConfigured)
    #expect(restoredModel.analysisRequestVersion == 0)
}

@MainActor
@Test
func analysisVisitsClampToSupportedRange() {
    let model = GokanAppModel(engine: SilentAnalysisEngine())

    model.analysisVisits = 0
    #expect(model.analysisVisits == GokanAppModel.analysisVisitsRange.lowerBound)

    model.analysisVisits = 50_000
    #expect(model.analysisVisits == GokanAppModel.analysisVisitsRange.upperBound)
}

@MainActor
@Test
func persistedAnalysisVisitsClampWithoutInvalidatingOnRestore() {
    let lowDefaults = isolatedDefaults()
    lowDefaults.userDefaults.set(0, forKey: "Gokan.analysis.visits")

    let lowModel = GokanAppModel(engine: SilentAnalysisEngine(), settingsDefaults: lowDefaults.userDefaults)

    #expect(lowModel.analysisVisits == GokanAppModel.analysisVisitsRange.lowerBound)
    #expect(lowModel.analysisRequestVersion == 0)

    let highDefaults = isolatedDefaults()
    highDefaults.userDefaults.set(50_000, forKey: "Gokan.analysis.visits")

    let highModel = GokanAppModel(engine: SilentAnalysisEngine(), settingsDefaults: highDefaults.userDefaults)

    #expect(highModel.analysisVisits == GokanAppModel.analysisVisitsRange.upperBound)
    #expect(highModel.analysisRequestVersion == 0)
}

@MainActor
@Test
func persistedIncompleteKataGoSettingsRestoreIncompleteStatus() {
    let defaults = isolatedDefaults()
    let firstModel = GokanAppModel(
        engine: SilentAnalysisEngine(),
        settingsDefaults: defaults.userDefaults,
        supportsKataGoSubprocess: true
    )

    firstModel.engineKind = .kataGo
    let restoredModel = GokanAppModel(
        engine: SilentAnalysisEngine(),
        settingsDefaults: defaults.userDefaults,
        supportsKataGoSubprocess: true
    )

    #expect(restoredModel.engineKind == .kataGo)
    #expect(restoredModel.kataGoSettings == KataGoPathSettings())
    #expect(restoredModel.engineStatus == .kataGoIncomplete(missingFields: ["executable path", "model path", "config path"]))
    #expect(restoredModel.analysisRequestVersion == 0)
}

@MainActor
@Test
func unknownPersistedEngineKindFallsBackToMock() {
    let defaults = isolatedDefaults()
    defaults.userDefaults.set("future-engine", forKey: "Gokan.analysisEngine.kind")
    defaults.userDefaults.set("/tmp/katago", forKey: "Gokan.kataGo.executablePath")

    let model = GokanAppModel(engine: SilentAnalysisEngine(), settingsDefaults: defaults.userDefaults)

    #expect(model.engineKind == .mock)
    #expect(model.kataGoSettings.executablePath == "/tmp/katago")
    #expect(model.engineStatus == .mock)
    #expect(model.analysisRequestVersion == 0)
}

@MainActor
@Test
func nonPersistentInjectedModelsDoNotShareEngineSettings() {
    let firstModel = GokanAppModel(engine: SilentAnalysisEngine())
    firstModel.engineKind = .kataGo
    firstModel.analysisVisits = 1_200
    firstModel.kataGoSettings = KataGoPathSettings(
        executablePath: "/usr/local/bin/katago",
        modelPath: "/models/g170.bin.gz",
        configPath: "/configs/analysis.cfg"
    )

    let secondModel = GokanAppModel(engine: SilentAnalysisEngine())

    #expect(secondModel.engineKind == .mock)
    #expect(secondModel.kataGoSettings == KataGoPathSettings())
    #expect(secondModel.analysisVisits == GokanAppModel.defaultAnalysisVisits)
    #expect(secondModel.engineStatus == .mock)
}

private struct SilentAnalysisEngine: GoAnalysisEngine {
    func analyze(_ request: AnalysisRequest) async throws -> AsyncThrowingStream<AnalysisSnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private struct ScriptedAnalysisEngine: GoAnalysisEngine {
    let snapshots: [AnalysisSnapshot]

    func analyze(_ request: AnalysisRequest) async throws -> AsyncThrowingStream<AnalysisSnapshot, Error> {
        AsyncThrowingStream { continuation in
            for snapshot in snapshots {
                continuation.yield(snapshot)
            }
            continuation.finish()
        }
    }
}

private final class RecordingAnalysisEngine: GoAnalysisEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: AnalysisRequest?

    var lastRequest: AnalysisRequest? {
        withLock {
            storedRequest
        }
    }

    func analyze(_ request: AnalysisRequest) async throws -> AsyncThrowingStream<AnalysisSnapshot, Error> {
        withLock {
            storedRequest = request
        }
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class ControlledAnalysisEngine: GoAnalysisEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var storedContinuation: AsyncThrowingStream<AnalysisSnapshot, Error>.Continuation?

    var hasContinuation: Bool {
        withLock {
            storedContinuation != nil
        }
    }

    func analyze(_ request: AnalysisRequest) async throws -> AsyncThrowingStream<AnalysisSnapshot, Error> {
        AsyncThrowingStream { continuation in
            withLock {
                storedContinuation = continuation
            }
        }
    }

    func yield(_ snapshot: AnalysisSnapshot) {
        _ = withLock {
            storedContinuation?.yield(snapshot)
        }
    }

    func finish() {
        withLock {
            storedContinuation?.finish()
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class EngineFactoryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var selections: [AnalysisEngineSelection] = []

    var callCount: Int {
        withLock {
            selections.count
        }
    }

    var lastSelection: AnalysisEngineSelection? {
        withLock {
            selections.last
        }
    }

    func makeEngine(selection: AnalysisEngineSelection) throws -> any GoAnalysisEngine {
        withLock {
            selections.append(selection)
        }
        return SilentAnalysisEngine()
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private func isolatedDefaults() -> IsolatedDefaults {
    let suiteName = "GokanAppModelTests.\(UUID().uuidString)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Could not create isolated UserDefaults suite.")
    }
    userDefaults.removePersistentDomain(forName: suiteName)
    return IsolatedDefaults(suiteName: suiteName, userDefaults: userDefaults)
}

private final class IsolatedDefaults {
    let suiteName: String
    let userDefaults: UserDefaults

    init(suiteName: String, userDefaults: UserDefaults) {
        self.suiteName = suiteName
        self.userDefaults = userDefaults
    }

    deinit {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

private func modelCatalog() throws -> GokanModelCatalog {
    try GokanModelCatalog(
        profiles: [
            GokanModelProfile(
                id: "tiny-dev",
                displayName: "Tiny Dev Model",
                modelFileName: "tiny.bin.gz",
                defaultConfigFileName: "analysis.cfg",
                checksum: try GokanModelChecksum(sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"),
                license: GokanModelLicense(name: "Fixture")
            ),
        ]
    )
}

private func modelOnlyCatalog() throws -> GokanModelCatalog {
    try GokanModelCatalog(
        profiles: [
            GokanModelProfile(
                id: "model-only",
                displayName: "Model Only",
                modelFileName: "model-only.bin.gz",
                license: GokanModelLicense(name: "Fixture")
            ),
        ]
    )
}

private func alternateModelCatalog() throws -> GokanModelCatalog {
    try GokanModelCatalog(
        profiles: [
            GokanModelProfile(
                id: "tiny-dev",
                displayName: "Alternate Tiny Dev Model",
                modelFileName: "alternate.bin.gz",
                defaultConfigFileName: "alternate-analysis.cfg",
                checksum: try GokanModelChecksum(sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"),
                license: GokanModelLicense(name: "Fixture")
            ),
        ]
    )
}

private func writeData(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private struct KataGoFileFixture {
    let executableURL: URL
    let modelURL: URL
    let configURL: URL

    var settings: KataGoPathSettings {
        KataGoPathSettings(
            executablePath: executableURL.path,
            modelPath: modelURL.path,
            configPath: configURL.path
        )
    }
}

private func makeKataGoFileFixture(
    in temporaryDirectory: TemporaryDirectory,
    prefix: String = "katago",
    modelName: String = "model.bin.gz",
    createExecutable: Bool = true,
    createModel: Bool = true,
    createConfig: Bool = true
) throws -> KataGoFileFixture {
    let rootURL = temporaryDirectory.url.appending(path: prefix)
    let fixture = KataGoFileFixture(
        executableURL: rootURL.appending(path: "bin/katago"),
        modelURL: rootURL.appending(path: "models/\(modelName)"),
        configURL: rootURL.appending(path: "configs/analysis.cfg")
    )

    if createExecutable {
        try writeData("katago", to: fixture.executableURL)
    }
    if createModel {
        try writeData("model", to: fixture.modelURL)
    }
    if createConfig {
        try writeData("config", to: fixture.configURL)
    }

    return fixture
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "gokan-ui-model-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private func snapshot(with points: [BoardPoint]) -> AnalysisSnapshot {
    AnalysisSnapshot(
        candidateMoves: points.enumerated().map { index, point in
            CandidateMove(
                point: point,
                policy: 0.5 - Double(index) * 0.05,
                winRate: 0.6 - Double(index) * 0.05,
                visits: 100 - index
            )
        },
        scoreLead: 1.5,
        completedVisits: 100
    )
}

private func sampleModelCatalogData() throws -> Data {
    let testsDirectory = URL(filePath: #filePath).deletingLastPathComponent()
    let packageRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: packageRoot.appending(path: "app/Shared/Resources/SampleModelCatalog.json"))
}

private enum FactoryError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Factory unavailable"
    }
}
