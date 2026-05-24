// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct GokanModelProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let modelFileName: String
    public let defaultConfigFileName: String?
    public let expectedByteCount: Int64?
    public let checksum: GokanModelChecksum?
    public let license: GokanModelLicense
    public let supportedBoardSizes: [GokanModelBoardSize]
    public let deviceSuitability: [GokanDeviceSuitability]

    public init(
        id: String,
        displayName: String,
        description: String? = nil,
        modelFileName: String,
        defaultConfigFileName: String? = nil,
        expectedByteCount: Int64? = nil,
        checksum: GokanModelChecksum? = nil,
        license: GokanModelLicense,
        supportedBoardSizes: [GokanModelBoardSize] = [],
        deviceSuitability: [GokanDeviceSuitability] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.modelFileName = modelFileName
        self.defaultConfigFileName = defaultConfigFileName
        self.expectedByteCount = expectedByteCount
        self.checksum = checksum
        self.license = license
        self.supportedBoardSizes = supportedBoardSizes
        self.deviceSuitability = deviceSuitability
    }
}

public struct GokanModelLicense: Codable, Equatable, Sendable {
    public let name: String
    public let noticeURL: URL?

    public init(name: String, noticeURL: URL? = nil) {
        self.name = name
        self.noticeURL = noticeURL
    }
}

public struct GokanModelBoardSize: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct GokanDeviceSuitability: Codable, Equatable, Sendable {
    public enum Platform: String, Codable, Sendable {
        case iOS
        case macOS
    }

    public enum Tier: String, Codable, Sendable {
        case small
        case balanced
        case large
    }

    public let platform: Platform
    public let tier: Tier
    public let note: String?

    public init(platform: Platform, tier: Tier, note: String? = nil) {
        self.platform = platform
        self.tier = tier
        self.note = note
    }
}
