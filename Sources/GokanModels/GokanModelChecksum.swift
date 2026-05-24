// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

public enum GokanModelChecksumError: Error, Equatable, Sendable {
    case invalidSHA256(String)
    case fileUnreadable(String)
}

public struct GokanModelChecksum: Codable, Equatable, Sendable {
    public enum Algorithm: String, Codable, Sendable {
        case sha256
    }

    public let algorithm: Algorithm
    public let value: String

    public init(sha256: String) throws {
        let normalized = sha256.lowercased()
        guard normalized.count == 64,
              normalized.allSatisfy({ $0.isHexDigit }) else {
            throw GokanModelChecksumError.invalidSHA256(sha256)
        }

        self.algorithm = .sha256
        self.value = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let algorithm = try container.decode(Algorithm.self, forKey: .algorithm)
        let value = try container.decode(String.self, forKey: .value)
        switch algorithm {
        case .sha256:
            try self.init(sha256: value)
        }
    }

    public static func sha256Hex(forFileAt url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw GokanModelChecksumError.fileUnreadable(url.path)
        }
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
