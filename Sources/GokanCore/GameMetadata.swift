// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct GameMetadata: Hashable, Sendable {
    public var blackPlayerName: String
    public var whitePlayerName: String
    public var komi: String
    public var result: String
    public var gameName: String
    public var event: String
    public var date: String

    public static let empty = GameMetadata()

    public init(
        blackPlayerName: String = "",
        whitePlayerName: String = "",
        komi: String = "",
        result: String = "",
        gameName: String = "",
        event: String = "",
        date: String = ""
    ) {
        self.blackPlayerName = blackPlayerName
        self.whitePlayerName = whitePlayerName
        self.komi = komi
        self.result = result
        self.gameName = gameName
        self.event = event
        self.date = date
    }

    public var isEmpty: Bool {
        blackPlayerName.isEmpty
            && whitePlayerName.isEmpty
            && komi.isEmpty
            && result.isEmpty
            && gameName.isEmpty
            && event.isEmpty
            && date.isEmpty
    }
}
