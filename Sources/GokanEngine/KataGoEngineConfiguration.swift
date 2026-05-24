// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct KataGoEngineConfiguration: Hashable, Sendable {
    public let executableURL: URL
    public let modelURL: URL
    public let configURL: URL

    public init(executableURL: URL, modelURL: URL, configURL: URL) {
        self.executableURL = executableURL
        self.modelURL = modelURL
        self.configURL = configURL
    }
}
