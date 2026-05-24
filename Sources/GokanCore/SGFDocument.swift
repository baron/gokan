// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum SGFDocumentError: Error, Equatable, Sendable {
    case missingGameTree
    case unsupportedGame
    case invalidBoardSize
    case illegalMove(moveNumber: Int, BoardError)
}

public struct SGFDocument: Hashable, Sendable {
    public var boardSize: BoardSize
    public var moves: [PlayedMove]

    public init(boardSize: BoardSize = .standard, moves: [PlayedMove] = []) {
        self.boardSize = boardSize
        self.moves = moves
    }

    public init(game: GameRecord) {
        self.boardSize = game.board.size
        self.moves = game.moves
    }

    public func gameRecord() throws -> GameRecord {
        var record = GameRecord(boardSize: boardSize)

        for (index, playedMove) in moves.enumerated() {
            do {
                try record.play(playedMove.move)
            } catch let error as BoardError {
                throw SGFDocumentError.illegalMove(moveNumber: index + 1, error)
            }
        }

        return record
    }

    public func serialize() throws -> String {
        var output = "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[\(boardSize.width)]"

        for move in moves {
            output += ";"
            output += move.color == .black ? "B" : "W"

            switch move.move {
            case .pass:
                output += "[]"
            case .play(let point):
                output += "[\(try SGFCoordinates.encode(point))]"
            }
        }

        output += ")\n"
        return output
    }

    public static func parse(_ source: String) throws -> SGFDocument {
        guard source.contains("(;") else {
            throw SGFDocumentError.missingGameTree
        }

        let properties = scanProperties(in: source)

        if let game = properties.first(where: { $0.identifier == "GM" })?.values.first, game != "1" {
            throw SGFDocumentError.unsupportedGame
        }

        let size = try parseBoardSize(from: properties.first(where: { $0.identifier == "SZ" })?.values.first)
        let moves = try properties.compactMap { property -> PlayedMove? in
            guard property.identifier == "B" || property.identifier == "W" else {
                return nil
            }

            let color: StoneColor = property.identifier == "B" ? .black : .white
            let value = property.values.first ?? ""
            let move: Move = value.isEmpty ? .pass : .play(try SGFCoordinates.decode(value))
            return PlayedMove(color: color, move: move)
        }

        let document = SGFDocument(boardSize: size, moves: moves)
        _ = try document.gameRecord()
        return document
    }

    private static func parseBoardSize(from value: String?) throws -> BoardSize {
        guard let value, value.isEmpty == false else {
            return .standard
        }

        if let size = Int(value) {
            return BoardSize(width: size, height: size)
        }

        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else {
            throw SGFDocumentError.invalidBoardSize
        }

        return BoardSize(width: parts[0], height: parts[1])
    }

    private static func scanProperties(in source: String) -> [SGFProperty] {
        var properties: [SGFProperty] = []
        var index = source.startIndex

        while index < source.endIndex {
            guard source[index].isUppercase else {
                index = source.index(after: index)
                continue
            }

            let identifierStart = index
            while index < source.endIndex, source[index].isUppercase {
                index = source.index(after: index)
            }

            let identifier = String(source[identifierStart..<index])
            var values: [String] = []

            while index < source.endIndex, source[index] == "[" {
                index = source.index(after: index)
                var value = ""

                while index < source.endIndex {
                    let character = source[index]
                    index = source.index(after: index)

                    if character == "\\" {
                        guard index < source.endIndex else {
                            break
                        }
                        value.append(source[index])
                        index = source.index(after: index)
                    } else if character == "]" {
                        break
                    } else {
                        value.append(character)
                    }
                }

                values.append(value)
            }

            properties.append(SGFProperty(identifier: identifier, values: values))
        }

        return properties
    }
}

private struct SGFProperty: Hashable, Sendable {
    let identifier: String
    let values: [String]
}
