// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct GokanModelCache: Equatable, Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func modelURL(for profile: GokanModelProfile) -> URL {
        rootURL.appending(path: "models").appending(path: safeRelativeFileName(profile.modelFileName))
    }

    public func configURL(for profile: GokanModelProfile) -> URL? {
        guard let defaultConfigFileName = profile.defaultConfigFileName else {
            return nil
        }

        return rootURL.appending(path: "configs").appending(path: safeRelativeFileName(defaultConfigFileName))
    }

    public func readiness(
        for profile: GokanModelProfile,
        fileManager: FileManager = .default
    ) -> GokanModelReadiness {
        let modelURL = modelURL(for: profile)
        guard fileManager.fileExists(atPath: modelURL.path) else {
            return .missingModel(modelURL: modelURL)
        }

        if let configURL = configURL(for: profile),
           fileManager.fileExists(atPath: configURL.path) == false {
            return .missingConfig(configURL: configURL)
        }

        return .ready(modelURL: modelURL, configURL: configURL(for: profile), checksum: profile.checksum)
    }

    public func verifyChecksum(for profile: GokanModelProfile) async -> GokanModelVerificationResult {
        let modelURL = modelURL(for: profile)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            return .missing(modelURL: modelURL)
        }
        guard let checksum = profile.checksum else {
            return .checksumUnavailable(modelURL: modelURL)
        }

        return await Task.detached {
            do {
                let actual = try GokanModelChecksum.sha256Hex(forFileAt: modelURL)
                if actual == checksum.value {
                    return .verified(modelURL: modelURL, expectedSHA256: checksum.value, actualSHA256: actual)
                }
                return .mismatch(modelURL: modelURL, expectedSHA256: checksum.value, actualSHA256: actual)
            } catch {
                return .failed(modelURL: modelURL, message: error.localizedDescription)
            }
        }.value
    }

    private func safeRelativeFileName(_ fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidNames: Set<String> = ["", ".", ".."]
        guard invalidNames.contains(trimmed) == false else {
            return "_invalid"
        }

        return trimmed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
    }
}

public enum GokanModelReadiness: Equatable, Sendable {
    case ready(modelURL: URL, configURL: URL?, checksum: GokanModelChecksum?)
    case missingModel(modelURL: URL)
    case missingConfig(configURL: URL)
}

public enum GokanModelVerificationResult: Equatable, Sendable {
    case checksumUnavailable(modelURL: URL)
    case verified(modelURL: URL, expectedSHA256: String, actualSHA256: String)
    case mismatch(modelURL: URL, expectedSHA256: String, actualSHA256: String)
    case missing(modelURL: URL)
    case failed(modelURL: URL, message: String)
}
