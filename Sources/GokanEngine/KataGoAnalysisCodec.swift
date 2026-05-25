// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GokanCore

internal struct KataGoAnalysisCodec: Sendable {
    init() {}

    func encode(_ request: AnalysisRequest, id: String) throws -> Data {
        let replayedBoard = try? boardByReplaying(request.moves, from: request.initialBoard)
        let shouldUseMoves = replayedBoard == request.board
        let initialPlayer = shouldUseMoves
            ? (request.moves.first?.color ?? request.nextPlayer)
            : request.nextPlayer
        let payload = KataGoAnalysisRequestPayload(
            id: id,
            rules: "japanese",
            komi: 6.5,
            boardXSize: request.board.size.width,
            boardYSize: request.board.size.height,
            initialPlayer: colorCode(for: initialPlayer),
            initialStones: try initialStones(from: shouldUseMoves ? request.initialBoard : request.board),
            moves: shouldUseMoves ? try request.moves.map { move in
                [
                    colorCode(for: move.color),
                    try coordinateString(for: move.move, boardSize: request.board.size),
                ]
            } : [],
            maxVisits: request.visits,
            includePolicy: true,
            includeOwnership: false
        )

        return try lineData(for: payload)
    }

    func encodeTerminate(id: String) throws -> Data {
        try lineData(for: KataGoAnalysisTerminatePayload(id: id))
    }

    func decode(_ line: Data) throws -> KataGoAnalysisResponse {
        do {
            return try JSONDecoder().decode(KataGoAnalysisResponse.self, from: line)
        } catch {
            let text = String(decoding: line.prefix(512), as: UTF8.self)
            throw KataGoEngineError.protocolViolation(reason: "Could not decode response line: \(text)")
        }
    }

    func snapshot(from response: KataGoAnalysisResponse, boardSize: BoardSize) throws -> AnalysisSnapshot {
        let candidates = try response.moveInfos.compactMap { moveInfo -> CandidateMove? in
            guard moveInfo.move.lowercased() != "pass" else {
                return nil
            }

            return CandidateMove(
                point: try KataGoCoordinates.point(from: moveInfo.move, boardSize: boardSize),
                policy: moveInfo.prior ?? 0,
                winRate: moveInfo.winrate ?? 0,
                visits: moveInfo.visits ?? 0
            )
        }

        return AnalysisSnapshot(
            candidateMoves: candidates,
            scoreLead: response.rootInfo?.scoreLead ?? 0,
            completedVisits: response.rootInfo?.visits ?? 0
        )
    }

    private func lineData<T: Encodable>(for payload: T) throws -> Data {
        var data = try JSONEncoder().encode(payload)
        data.append(0x0A)
        return data
    }

    private func colorCode(for color: StoneColor) -> String {
        color == .black ? "B" : "W"
    }

    private func coordinateString(for move: Move, boardSize: BoardSize) throws -> String {
        switch move {
        case .play(let point):
            try KataGoCoordinates.string(from: point, boardSize: boardSize)
        case .pass:
            "pass"
        }
    }

    private func boardByReplaying(_ moves: [PlayedMove], from initialBoard: GoBoard) throws -> GoBoard {
        try moves.reduce(initialBoard) { board, playedMove in
            switch playedMove.move {
            case .play(let point):
                try board.placing(playedMove.color, at: point)
            case .pass:
                board
            }
        }
    }

    private func initialStones(from board: GoBoard) throws -> [[String]] {
        try board.occupiedPoints.compactMap { point in
            guard let color = board[point] else {
                return nil
            }
            return [
                colorCode(for: color),
                try KataGoCoordinates.string(from: point, boardSize: board.size),
            ]
        }
    }
}
