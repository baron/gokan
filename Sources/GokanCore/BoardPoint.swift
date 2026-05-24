// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct BoardPoint: Hashable, Sendable, Identifiable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public var id: String {
        "\(x),\(y)"
    }
}

public struct BoardSize: Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int = 19, height: Int = 19) {
        precondition(width > 1)
        precondition(height > 1)
        self.width = width
        self.height = height
    }

    public static let standard = BoardSize(width: 19, height: 19)

    public func contains(_ point: BoardPoint) -> Bool {
        point.x >= 0 && point.y >= 0 && point.x < width && point.y < height
    }

    public var points: [BoardPoint] {
        (0..<height).flatMap { y in
            (0..<width).map { x in
                BoardPoint(x: x, y: y)
            }
        }
    }
}
