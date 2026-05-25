// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The owner of an empty board region under static territory scoring.
public enum TerritoryOwner: Hashable, Sendable {
    case black
    case white
    case neutral

    init(adjacentColors: Set<StoneColor>) {
        if adjacentColors == [.black] {
            self = .black
        } else if adjacentColors == [.white] {
            self = .white
        } else {
            self = .neutral
        }
    }
}

/// A deterministic area estimate for a single board position.
///
/// This is a static area reachability estimate: stones plus empty regions that
/// are adjacent to only one color, with komi added to White. It does not infer
/// dead stones or life and death.
public struct ScoreEstimate: Hashable, Sendable {
    public let blackStones: Int
    public let whiteStones: Int
    public let blackTerritory: Int
    public let whiteTerritory: Int
    public let neutralPoints: Int
    public let komi: Double

    public init(
        blackStones: Int,
        whiteStones: Int,
        blackTerritory: Int,
        whiteTerritory: Int,
        neutralPoints: Int,
        komi: Double
    ) {
        self.blackStones = blackStones
        self.whiteStones = whiteStones
        self.blackTerritory = blackTerritory
        self.whiteTerritory = whiteTerritory
        self.neutralPoints = neutralPoints
        self.komi = komi
    }

    public var blackAreaScore: Double {
        Double(blackStones + blackTerritory)
    }

    public var whiteAreaScore: Double {
        Double(whiteStones + whiteTerritory) + komi
    }

    /// Positive values favor Black; negative values favor White.
    public var scoreLead: Double {
        blackAreaScore - whiteAreaScore
    }
}

/// Static Go board scoring helpers.
public enum GoScorer {
    /// Estimates area score by flood-filling empty regions and assigning each
    /// region to the sole adjacent color, or neutral when adjacent to both
    /// colors or no stones.
    public static func estimate(board: GoBoard, komi: Double = 0) -> ScoreEstimate {
        var visitedEmptyPoints: Set<BoardPoint> = []
        var blackStones = 0
        var whiteStones = 0
        var blackTerritory = 0
        var whiteTerritory = 0
        var neutralPoints = 0

        for point in board.size.points {
            switch board[point] {
            case .black:
                blackStones += 1
            case .white:
                whiteStones += 1
            case nil:
                guard visitedEmptyPoints.contains(point) == false else {
                    continue
                }
                let region = emptyRegion(containing: point, on: board)
                visitedEmptyPoints.formUnion(region.points)
                switch region.owner {
                case .black:
                    blackTerritory += region.points.count
                case .white:
                    whiteTerritory += region.points.count
                case .neutral:
                    neutralPoints += region.points.count
                }
            }
        }

        return ScoreEstimate(
            blackStones: blackStones,
            whiteStones: whiteStones,
            blackTerritory: blackTerritory,
            whiteTerritory: whiteTerritory,
            neutralPoints: neutralPoints,
            komi: komi
        )
    }

    private struct EmptyRegion {
        var points: Set<BoardPoint>
        var owner: TerritoryOwner
    }

    private static func emptyRegion(containing start: BoardPoint, on board: GoBoard) -> EmptyRegion {
        var points: Set<BoardPoint> = []
        var adjacentColors: Set<StoneColor> = []
        var frontier = [start]

        while let point = frontier.popLast() {
            guard points.insert(point).inserted else {
                continue
            }

            for neighbor in board.neighbors(of: point) {
                if let color = board[neighbor] {
                    adjacentColors.insert(color)
                } else if points.contains(neighbor) == false {
                    frontier.append(neighbor)
                }
            }
        }

        return EmptyRegion(points: points, owner: TerritoryOwner(adjacentColors: adjacentColors))
    }
}
