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

private struct SilentAnalysisEngine: GoAnalysisEngine {
    func analyze(_ request: AnalysisRequest) async throws -> AsyncThrowingStream<AnalysisSnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
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
