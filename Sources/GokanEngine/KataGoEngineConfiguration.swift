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

    public func validateFilePresence(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw KataGoEngineError.executableMissing(executableURL)
        }
        guard fileManager.fileExists(atPath: modelURL.path) else {
            throw KataGoEngineError.modelMissing(modelURL)
        }
        guard fileManager.fileExists(atPath: configURL.path) else {
            throw KataGoEngineError.configMissing(configURL)
        }
    }
}
