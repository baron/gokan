// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import GokanCore

@Test
func emptyBoardScoresAllPointsAsNeutral() {
    let board = GoBoard(size: BoardSize(width: 9, height: 9))

    let estimate = GoScorer.estimate(board: board, komi: 6.5)

    #expect(estimate.blackStones == 0)
    #expect(estimate.whiteStones == 0)
    #expect(estimate.blackTerritory == 0)
    #expect(estimate.whiteTerritory == 0)
    #expect(estimate.neutralPoints == 81)
    #expect(estimate.blackAreaScore == 0)
    #expect(estimate.whiteAreaScore == 6.5)
    #expect(estimate.scoreLead == -6.5)
}

@Test
func loneStoneOwnsReachableAreaUnderStaticAreaScoring() throws {
    let board = try GoBoard(size: BoardSize(width: 3, height: 3))
        .placing(.black, at: BoardPoint(x: 1, y: 1))

    let estimate = GoScorer.estimate(board: board)

    #expect(estimate.blackStones == 1)
    #expect(estimate.blackTerritory == 8)
    #expect(estimate.blackAreaScore == 9)
    #expect(estimate.neutralPoints == 0)
}

@Test
func singlePointEyeCountsAsBlackTerritory() throws {
    let eye = BoardPoint(x: 1, y: 1)
    let size = BoardSize(width: 3, height: 3)
    let stones = Dictionary(
        uniqueKeysWithValues: size.points
            .filter { $0 != eye }
            .map { ($0, StoneColor.black) }
    )
    let board = GoBoard(size: size, stones: stones)

    let estimate = GoScorer.estimate(board: board)

    #expect(board[eye] == nil)
    #expect(estimate.blackStones == 8)
    #expect(estimate.blackTerritory == 1)
    #expect(estimate.whiteTerritory == 0)
    #expect(estimate.neutralPoints == 0)
    #expect(estimate.blackAreaScore == 9)
}

@Test
func regionAdjacentToBothColorsIsNeutral() throws {
    var board = GoBoard(size: BoardSize(width: 3, height: 3))
    board = try board.placing(.black, at: BoardPoint(x: 0, y: 1))
    board = try board.placing(.white, at: BoardPoint(x: 2, y: 1))

    let estimate = GoScorer.estimate(board: board)

    #expect(estimate.blackStones == 1)
    #expect(estimate.whiteStones == 1)
    #expect(estimate.blackTerritory == 0)
    #expect(estimate.whiteTerritory == 0)
    #expect(estimate.neutralPoints == 7)
    #expect(estimate.scoreLead == 0)
}

@Test
func whiteTerritoryAndKomiShiftScoreLeadTowardWhite() throws {
    let eye = BoardPoint(x: 1, y: 1)
    let size = BoardSize(width: 3, height: 3)
    let stones = Dictionary(
        uniqueKeysWithValues: size.points
            .filter { $0 != eye }
            .map { ($0, StoneColor.white) }
    )
    let board = GoBoard(size: size, stones: stones)

    let estimate = GoScorer.estimate(board: board, komi: 6.5)

    #expect(estimate.whiteStones == 8)
    #expect(estimate.whiteTerritory == 1)
    #expect(estimate.whiteAreaScore == 15.5)
    #expect(estimate.scoreLead == -15.5)
}
