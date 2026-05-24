// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum StoneColor: String, Hashable, Sendable, CaseIterable {
    case black
    case white

    public var opponent: StoneColor {
        self == .black ? .white : .black
    }
}

public enum Move: Hashable, Sendable {
    case play(BoardPoint)
    case pass
}

public enum BoardError: Error, Equatable, Sendable {
    case pointOutOfBounds
    case occupiedPoint
    case suicide
}

public struct GoBoard: Hashable, Sendable {
    public let size: BoardSize
    private var stones: [BoardPoint: StoneColor]

    public init(size: BoardSize = .standard, stones: [BoardPoint: StoneColor] = [:]) {
        self.size = size
        self.stones = stones
    }

    public subscript(_ point: BoardPoint) -> StoneColor? {
        stones[point]
    }

    public var occupiedPoints: [BoardPoint] {
        stones.keys.sorted { lhs, rhs in
            lhs.y == rhs.y ? lhs.x < rhs.x : lhs.y < rhs.y
        }
    }

    public func placing(_ color: StoneColor, at point: BoardPoint) throws -> GoBoard {
        guard size.contains(point) else {
            throw BoardError.pointOutOfBounds
        }
        guard stones[point] == nil else {
            throw BoardError.occupiedPoint
        }

        var next = self
        next.stones[point] = color

        for neighbor in next.neighbors(of: point) where next.stones[neighbor] == color.opponent {
            if next.liberties(of: neighbor).isEmpty {
                next.removeGroup(containing: neighbor)
            }
        }

        if next.liberties(of: point).isEmpty {
            throw BoardError.suicide
        }

        return next
    }

    public func neighbors(of point: BoardPoint) -> [BoardPoint] {
        [
            BoardPoint(x: point.x - 1, y: point.y),
            BoardPoint(x: point.x + 1, y: point.y),
            BoardPoint(x: point.x, y: point.y - 1),
            BoardPoint(x: point.x, y: point.y + 1),
        ].filter(size.contains)
    }

    public func group(containing point: BoardPoint) -> Set<BoardPoint> {
        guard let color = stones[point] else {
            return []
        }

        var seen: Set<BoardPoint> = []
        var frontier = [point]

        while let current = frontier.popLast() {
            guard seen.insert(current).inserted else {
                continue
            }

            for neighbor in neighbors(of: current) where stones[neighbor] == color {
                frontier.append(neighbor)
            }
        }

        return seen
    }

    public func liberties(of point: BoardPoint) -> Set<BoardPoint> {
        group(containing: point).reduce(into: Set<BoardPoint>()) { result, stone in
            for neighbor in neighbors(of: stone) where stones[neighbor] == nil {
                result.insert(neighbor)
            }
        }
    }

    private mutating func removeGroup(containing point: BoardPoint) {
        for stone in group(containing: point) {
            stones.removeValue(forKey: stone)
        }
    }
}
