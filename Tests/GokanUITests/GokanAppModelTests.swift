// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GokanCore
import GokanEngine
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
func staleAnalysisDoesNotOverwriteNewerPosition() async throws {
    let engine = ControlledAnalysisEngine()
    let model = GokanAppModel(engine: engine)

    let analysisTask = Task {
        await model.analyze()
    }

    while engine.hasContinuation == false {
        try await Task.sleep(nanoseconds: 1_000_000)
    }

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
    let model = GokanAppModel(engineFactory: probe.makeEngine(selection:))

    model.engineKind = .kataGo
    await model.analyze()

    #expect(model.engineStatus == .kataGoIncomplete(missingFields: ["executable path", "model path", "config path"]))
    #expect(model.analysisError == EngineStatus.kataGoIncomplete(missingFields: ["executable path", "model path", "config path"]).message)
    #expect(probe.callCount == 0)
}

@MainActor
@Test
func configuredKataGoSelectionIsPassedToEngineFactory() throws {
    let probe = EngineFactoryProbe()
    let model = GokanAppModel(engineFactory: probe.makeEngine(selection:))

    model.engineKind = .kataGo
    model.kataGoSettings = KataGoPathSettings(
        executablePath: "/usr/local/bin/katago",
        modelPath: "/models/model.bin.gz",
        configPath: "/configs/analysis.cfg"
    )
    _ = try model.makeAnalysisEngine()

    #expect(model.engineStatus == .kataGoConfigured)
    #expect(probe.callCount == 1)
    #expect(
        probe.lastSelection == AnalysisEngineSelection(
            kind: .kataGo,
            kataGoSettings: KataGoPathSettings(
                executablePath: "/usr/local/bin/katago",
                modelPath: "/models/model.bin.gz",
                configPath: "/configs/analysis.cfg"
            )
        )
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
}

@MainActor
@Test
func engineSettingsPersistAcrossModelInstances() {
    let defaults = isolatedDefaults()
    let settings = KataGoPathSettings(
        executablePath: "/usr/local/bin/katago",
        modelPath: "/models/g170.bin.gz",
        configPath: "/configs/analysis.cfg"
    )
    let firstModel = GokanAppModel(engine: SilentAnalysisEngine(), settingsDefaults: defaults.userDefaults)

    firstModel.engineKind = .kataGo
    firstModel.kataGoSettings = settings
    let restoredModel = GokanAppModel(engine: SilentAnalysisEngine(), settingsDefaults: defaults.userDefaults)

    #expect(restoredModel.engineKind == .kataGo)
    #expect(restoredModel.kataGoSettings == settings)
    #expect(restoredModel.engineStatus == .kataGoConfigured)
    #expect(restoredModel.analysisRequestVersion == 0)
}

@MainActor
@Test
func persistedIncompleteKataGoSettingsRestoreIncompleteStatus() {
    let defaults = isolatedDefaults()
    let firstModel = GokanAppModel(engine: SilentAnalysisEngine(), settingsDefaults: defaults.userDefaults)

    firstModel.engineKind = .kataGo
    let restoredModel = GokanAppModel(engine: SilentAnalysisEngine(), settingsDefaults: defaults.userDefaults)

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
    firstModel.kataGoSettings = KataGoPathSettings(
        executablePath: "/usr/local/bin/katago",
        modelPath: "/models/g170.bin.gz",
        configPath: "/configs/analysis.cfg"
    )

    let secondModel = GokanAppModel(engine: SilentAnalysisEngine())

    #expect(secondModel.engineKind == .mock)
    #expect(secondModel.kataGoSettings == KataGoPathSettings())
    #expect(secondModel.engineStatus == .mock)
}

private struct SilentAnalysisEngine: GoAnalysisEngine {
    func analyze(_ request: AnalysisRequest) async throws -> AsyncThrowingStream<AnalysisSnapshot, Error> {
        AsyncThrowingStream { continuation in
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

private enum FactoryError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Factory unavailable"
    }
}
