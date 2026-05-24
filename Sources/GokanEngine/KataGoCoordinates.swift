// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GokanCore

internal enum KataGoCoordinates {
    private static let columns = Array("ABCDEFGHJKLMNOPQRSTUVWXYZ")

    static func string(from point: BoardPoint, boardSize: BoardSize) throws -> String {
        guard boardSize.contains(point), point.x < columns.count else {
            throw KataGoEngineError.protocolViolation(reason: "Point is outside the board.")
        }

        return "\(columns[point.x])\(boardSize.height - point.y)"
    }

    static func point(from string: String, boardSize: BoardSize) throws -> BoardPoint {
        guard string.lowercased() != "pass" else {
            throw KataGoEngineError.protocolViolation(reason: "Pass is not a board point.")
        }
        guard let column = string.first?.uppercased().first,
              let x = columns.firstIndex(of: column) else {
            throw KataGoEngineError.protocolViolation(reason: "Invalid KataGo coordinate column: \(string)")
        }

        let rowText = String(string.dropFirst())
        guard let row = Int(rowText) else {
            throw KataGoEngineError.protocolViolation(reason: "Invalid KataGo coordinate row: \(string)")
        }

        let point = BoardPoint(x: x, y: boardSize.height - row)
        guard boardSize.contains(point) else {
            throw KataGoEngineError.protocolViolation(reason: "KataGo coordinate outside board: \(string)")
        }
        return point
    }
}
