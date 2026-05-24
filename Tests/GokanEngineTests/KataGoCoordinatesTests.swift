// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import GokanCore
@testable import GokanEngine

@Test
func kataGoCoordinatesSkipIColumnAndUseBottomRows() throws {
    let size = BoardSize.standard

    #expect(try KataGoCoordinates.point(from: "A1", boardSize: size) == BoardPoint(x: 0, y: 18))
    #expect(try KataGoCoordinates.point(from: "T19", boardSize: size) == BoardPoint(x: 18, y: 0))
    #expect(try KataGoCoordinates.point(from: "Q4", boardSize: size) == BoardPoint(x: 15, y: 15))
    #expect(try KataGoCoordinates.string(from: BoardPoint(x: 15, y: 15), boardSize: size) == "Q4")
}

