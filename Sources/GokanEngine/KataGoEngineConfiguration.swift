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

public struct KataGoAnalysisEngine: GoAnalysisEngine {
    public let configuration: KataGoEngineConfiguration

    public init(configuration: KataGoEngineConfiguration) {
        self.configuration = configuration
    }

    public func analyze(_ request: AnalysisRequest) async throws -> AsyncThrowingStream<AnalysisSnapshot, Error> {
        // The process boundary is intentionally a placeholder until the JSON
        // analysis protocol adapter can be tested against a built Metal binary.
        try await MockAnalysisEngine().analyze(request)
    }
}
