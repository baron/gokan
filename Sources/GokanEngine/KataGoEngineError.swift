// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum KataGoEngineError: Error, Sendable, CustomStringConvertible, LocalizedError {
    case platformUnsupported
    case executableMissing(URL)
    case modelMissing(URL)
    case configMissing(URL)
    case startupFailed(reason: String)
    case protocolViolation(reason: String)
    case engineTerminated(exitCode: Int32, stderrTail: String)

    public var description: String {
        switch self {
        case .platformUnsupported:
            "KataGo subprocess analysis is not supported on this platform."
        case .executableMissing(let url):
            "KataGo executable was not found at \(url.path)."
        case .modelMissing(let url):
            "KataGo model was not found at \(url.path)."
        case .configMissing(let url):
            "KataGo config was not found at \(url.path)."
        case .startupFailed(let reason):
            "KataGo failed to start: \(reason)"
        case .protocolViolation(let reason):
            "KataGo analysis protocol violation: \(reason)"
        case .engineTerminated(let exitCode, let stderrTail):
            "KataGo terminated with exit code \(exitCode): \(stderrTail)"
        }
    }

    public var errorDescription: String? {
        description
    }
}
