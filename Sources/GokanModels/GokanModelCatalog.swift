// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum GokanModelCatalogError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case duplicateProfileID(String)
    case invalidProfile(id: String, reason: String)
    case decodeFailed(String)
}

extension GokanModelCatalogError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported model catalog schema version \(version)."
        case .duplicateProfileID(let id):
            "Model catalog contains duplicate profile id \(id)."
        case .invalidProfile(let id, let reason):
            "Model catalog profile \(id) is invalid: \(reason)"
        case .decodeFailed(let message):
            "Could not decode model catalog: \(message)"
        }
    }
}

public struct GokanModelCatalog: Codable, Equatable, Sendable {
    public static let supportedSchemaVersion = 1
    public static let empty = try! GokanModelCatalog(profiles: [])

    public let schemaVersion: Int
    public let profiles: [GokanModelProfile]

    public init(schemaVersion: Int = supportedSchemaVersion, profiles: [GokanModelProfile]) throws {
        self.schemaVersion = schemaVersion
        self.profiles = try Self.validatedProfiles(profiles, schemaVersion: schemaVersion)
    }

    public static func decode(from data: Data) throws -> GokanModelCatalog {
        do {
            return try JSONDecoder().decode(GokanModelCatalog.self, from: data)
        } catch let error as GokanModelCatalogError {
            throw error
        } catch {
            throw GokanModelCatalogError.decodeFailed(error.localizedDescription)
        }
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public func profile(id: String) -> GokanModelProfile? {
        profiles.first { $0.id == id }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let profiles = try container.decode([GokanModelProfile].self, forKey: .profiles)
        try self.init(schemaVersion: schemaVersion, profiles: profiles)
    }

    private static func validatedProfiles(
        _ profiles: [GokanModelProfile],
        schemaVersion: Int
    ) throws -> [GokanModelProfile] {
        guard schemaVersion == supportedSchemaVersion else {
            throw GokanModelCatalogError.unsupportedSchemaVersion(schemaVersion)
        }

        var seenIDs: Set<String> = []
        var validated: [GokanModelProfile] = []
        for profile in profiles {
            let id = profile.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard id.isEmpty == false else {
                throw GokanModelCatalogError.invalidProfile(id: profile.id, reason: "Profile id is empty.")
            }
            guard id == profile.id else {
                throw GokanModelCatalogError.invalidProfile(id: profile.id, reason: "Profile id has leading or trailing whitespace.")
            }
            guard seenIDs.insert(id).inserted else {
                throw GokanModelCatalogError.duplicateProfileID(id)
            }
            let displayName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard displayName.isEmpty == false else {
                throw GokanModelCatalogError.invalidProfile(id: id, reason: "Display name is empty.")
            }
            guard displayName == profile.displayName else {
                throw GokanModelCatalogError.invalidProfile(id: id, reason: "Display name has leading or trailing whitespace.")
            }
            try validateFileName(profile.modelFileName, profileID: id, field: "modelFileName")
            if let configFileName = profile.defaultConfigFileName {
                try validateFileName(configFileName, profileID: id, field: "defaultConfigFileName")
            }
            validated.append(profile)
        }
        return validated
    }

    private static func validateFileName(_ fileName: String, profileID: String, field: String) throws {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidNames: Set<String> = ["", ".", ".."]
        guard trimmed == fileName,
              invalidNames.contains(trimmed) == false,
              trimmed.contains("/") == false,
              trimmed.contains("\\") == false else {
            throw GokanModelCatalogError.invalidProfile(
                id: profileID,
                reason: "\(field) must be a safe relative file name."
            )
        }
    }
}
