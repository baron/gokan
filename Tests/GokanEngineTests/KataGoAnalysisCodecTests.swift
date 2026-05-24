// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GokanCore
@testable import GokanEngine

@Test
func codecEncodesAnalysisRequestAsJsonLine() throws {
    var game = GameRecord(boardSize: BoardSize(width: 9, height: 9))
    try game.play(.play(BoardPoint(x: 4, y: 4)))

    let data = try KataGoAnalysisCodec().encode(
        AnalysisRequest(board: game.board, moves: game.moves, visits: 123),
        id: "request-1"
    )

    #expect(data.last == 0x0A)

    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(object["id"] as? String == "request-1")
    #expect(object["rules"] as? String == "japanese")
    #expect(object["boardXSize"] as? Int == 9)
    #expect(object["boardYSize"] as? Int == 9)
    #expect(object["maxVisits"] as? Int == 123)

    let moves = try #require(object["moves"] as? [[String]])
    #expect(moves == [["B", "E5"]])
}

@Test
func codecEncodesNonReplayableBoardAsInitialStones() throws {
    let board = GoBoard(
        size: BoardSize(width: 9, height: 9),
        stones: [BoardPoint(x: 4, y: 4): .black]
    )

    let data = try KataGoAnalysisCodec().encode(
        AnalysisRequest(board: board, moves: [], visits: 100),
        id: "setup-position"
    )
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    let initialStones = try #require(object["initialStones"] as? [[String]])
    let moves = try #require(object["moves"] as? [[String]])
    #expect(initialStones == [["B", "E5"]])
    #expect(moves.isEmpty)
}

@Test
func codecDecodesAnalysisResponseIntoSnapshot() throws {
    let line = Data(
        """
        {"id":"request-1","isDuringSearch":false,"rootInfo":{"scoreLead":1.25,"visits":40},"moveInfos":[{"move":"Q4","winrate":0.55,"prior":0.31,"visits":18},{"move":"pass","winrate":0.50,"prior":0.01,"visits":1}]}
        """.utf8
    )

    let codec = KataGoAnalysisCodec()
    let response = try codec.decode(line)
    let snapshot = try codec.snapshot(from: response, boardSize: .standard)

    #expect(response.id == "request-1")
    #expect(response.isDuringSearch == false)
    #expect(snapshot.scoreLead == 1.25)
    #expect(snapshot.completedVisits == 40)
    #expect(snapshot.candidateMoves.count == 1)
    #expect(snapshot.candidateMoves[0].point == BoardPoint(x: 15, y: 15))
    #expect(snapshot.candidateMoves[0].policy == 0.31)
    #expect(snapshot.candidateMoves[0].winRate == 0.55)
    #expect(snapshot.candidateMoves[0].visits == 18)
}

@Test
func codecReportsMalformedJsonAsProtocolViolation() throws {
    do {
        _ = try KataGoAnalysisCodec().decode(Data("{".utf8))
        Issue.record("Expected malformed JSON to throw.")
    } catch KataGoEngineError.protocolViolation(let reason) {
        #expect(reason.contains("Could not decode response line"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
