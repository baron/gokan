// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import GokanCore
import GokanEngine
@testable import GokanUI

@Test
func boardIntersectionTapSelectsVisibleCandidate() {
    let point = BoardPoint(x: 3, y: 3)
    let candidate = CandidateMove(point: point, policy: 0.42, winRate: 0.61, visits: 120)

    let action = boardIntersectionTapAction(point: point, color: nil, candidate: candidate)

    #expect(action == .selectCandidate(candidate))
}

@Test
func boardIntersectionTapPlaysNonCandidatePoint() {
    let point = BoardPoint(x: 3, y: 3)

    let action = boardIntersectionTapAction(point: point, color: nil, candidate: nil)

    #expect(action == .play(point))
}

@Test
func boardIntersectionTapPreservesNormalPlayForOccupiedPoint() {
    let point = BoardPoint(x: 3, y: 3)
    let candidate = CandidateMove(point: point, policy: 0.42, winRate: 0.61, visits: 120)

    let action = boardIntersectionTapAction(point: point, color: .black, candidate: candidate)

    #expect(action == .play(point))
}
