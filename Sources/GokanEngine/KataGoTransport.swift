// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

internal protocol KataGoTransport: Sendable {
    func start() async throws
    func send(_ line: Data) async throws
    func responses() -> AsyncThrowingStream<Data, Error>
    func stop() async
}

internal enum KataGoTransportFactory {
    static func make(for configuration: KataGoEngineConfiguration) throws -> any KataGoTransport {
        #if os(macOS)
        try validate(configuration)
        return ProcessKataGoTransport(configuration: configuration)
        #else
        throw KataGoEngineError.platformUnsupported
        #endif
    }

    static func validate(
        _ configuration: KataGoEngineConfiguration,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: configuration.executableURL.path) else {
            throw KataGoEngineError.executableMissing(configuration.executableURL)
        }
        guard fileManager.fileExists(atPath: configuration.modelURL.path) else {
            throw KataGoEngineError.modelMissing(configuration.modelURL)
        }
        guard fileManager.fileExists(atPath: configuration.configURL.path) else {
            throw KataGoEngineError.configMissing(configuration.configURL)
        }
    }
}
