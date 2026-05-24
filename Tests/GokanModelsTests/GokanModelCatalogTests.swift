// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GokanModels

@Test
func catalogDecodesValidMetadataAndRoundTrips() throws {
    let data = Data(
        """
        {
          "schemaVersion": 1,
          "profiles": [
            {
              "id": "tiny-dev",
              "displayName": "Tiny Dev Model",
              "description": "Fixture-sized profile metadata.",
              "modelFileName": "tiny.bin.gz",
              "defaultConfigFileName": "analysis.cfg",
              "expectedByteCount": 5,
              "checksum": {
                "algorithm": "sha256",
                "value": "2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824"
              },
              "license": {
                "name": "Model notice",
                "noticeURL": "https://example.com/model-notice"
              },
              "supportedBoardSizes": [
                { "width": 19, "height": 19 }
              ],
              "deviceSuitability": [
                { "platform": "macOS", "tier": "small", "note": "Fixture only" }
              ]
            }
          ]
        }
        """.utf8
    )

    let catalog = try GokanModelCatalog.decode(from: data)
    let profile = try #require(catalog.profile(id: "tiny-dev"))
    let encoded = try catalog.encode()
    let decodedAgain = try GokanModelCatalog.decode(from: encoded)

    #expect(catalog == decodedAgain)
    #expect(profile.displayName == "Tiny Dev Model")
    #expect(profile.modelFileName == "tiny.bin.gz")
    #expect(profile.defaultConfigFileName == "analysis.cfg")
    #expect(profile.checksum?.value == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    #expect(profile.license.name == "Model notice")
    #expect(profile.supportedBoardSizes == [GokanModelBoardSize(width: 19, height: 19)])
    #expect(profile.deviceSuitability == [
        GokanDeviceSuitability(platform: .macOS, tier: .small, note: "Fixture only"),
    ])
}

@Test
func sampleModelCatalogResourceDecodesAsMetadataOnlyProfiles() throws {
    let catalog = try GokanModelCatalog.decode(from: sampleModelCatalogData())

    #expect(catalog.schemaVersion == 1)
    #expect(catalog.profiles.map(\.id) == [
        "sample-9x9-metadata",
        "sample-19x19-metadata",
    ])

    let smallProfile = try #require(catalog.profile(id: "sample-9x9-metadata"))
    #expect(smallProfile.displayName == "Sample 9x9 Metadata Profile")
    #expect(smallProfile.modelFileName == "sample-9x9.bin.gz")
    #expect(smallProfile.defaultConfigFileName == "sample-analysis.cfg")
    #expect(smallProfile.expectedByteCount == nil)
    #expect(smallProfile.checksum == nil)
    #expect(smallProfile.license.name == "Sample metadata only - no model distributed")
    #expect(smallProfile.supportedBoardSizes == [GokanModelBoardSize(width: 9, height: 9)])

    let fullProfile = try #require(catalog.profile(id: "sample-19x19-metadata"))
    #expect(fullProfile.displayName == "Sample 19x19 Metadata Profile")
    #expect(fullProfile.modelFileName == "sample-19x19.bin.gz")
    #expect(fullProfile.defaultConfigFileName == "sample-analysis.cfg")
    #expect(fullProfile.expectedByteCount == nil)
    #expect(fullProfile.checksum == nil)
    #expect(fullProfile.supportedBoardSizes == [GokanModelBoardSize(width: 19, height: 19)])
}

@Test
func catalogRejectsUnsupportedSchemaVersion() {
    #expect(throws: GokanModelCatalogError.unsupportedSchemaVersion(2)) {
        try GokanModelCatalog(schemaVersion: 2, profiles: [])
    }
}

@Test
func catalogRejectsDuplicateProfileIDs() throws {
    let profile = try fixtureProfile(id: "duplicate")

    #expect(throws: GokanModelCatalogError.duplicateProfileID("duplicate")) {
        try GokanModelCatalog(profiles: [profile, profile])
    }
}

@Test(
    arguments: [
        "",
        ".",
        "..",
        " tiny.bin.gz ",
        "../model.bin.gz",
        "models/model.bin.gz",
        "models\\model.bin.gz",
    ]
)
func catalogRejectsUnsafeModelFileNames(fileName: String) throws {
    let profile = try fixtureProfile(modelFileName: fileName)

    #expect(throws: GokanModelCatalogError.self) {
        try GokanModelCatalog(profiles: [profile])
    }
}

@Test
func checksumRejectsInvalidSHA256() {
    #expect(throws: GokanModelChecksumError.invalidSHA256("not-a-sha")) {
        try GokanModelChecksum(sha256: "not-a-sha")
    }
}

@Test
func catalogRejectsWhitespacePaddedProfileIdentity() throws {
    #expect(throws: GokanModelCatalogError.self) {
        try GokanModelCatalog(profiles: [try fixtureProfile(id: " tiny-dev")])
    }
    #expect(throws: GokanModelCatalogError.self) {
        try GokanModelCatalog(
            profiles: [
                GokanModelProfile(
                    id: "tiny-dev",
                    displayName: " Tiny Dev Model ",
                    modelFileName: "tiny.bin.gz",
                    license: GokanModelLicense(name: "Fixture")
                ),
            ]
        )
    }
}

@Test
func catalogErrorsExposeLocalizedDescriptions() {
    #expect(
        GokanModelCatalogError.unsupportedSchemaVersion(2).localizedDescription
            == "Unsupported model catalog schema version 2."
    )
    #expect(
        GokanModelCatalogError.duplicateProfileID("tiny-dev").localizedDescription
            == "Model catalog contains duplicate profile id tiny-dev."
    )
    #expect(
        GokanModelCatalogError.invalidProfile(id: "tiny-dev", reason: "Display name is empty.").localizedDescription
            == "Model catalog profile tiny-dev is invalid: Display name is empty."
    )
    #expect(
        GokanModelCatalogError.decodeFailed("bad JSON").localizedDescription
            == "Could not decode model catalog: bad JSON"
    )
}

private func fixtureProfile(
    id: String = "tiny-dev",
    modelFileName: String = "tiny.bin.gz"
) throws -> GokanModelProfile {
    GokanModelProfile(
        id: id,
        displayName: "Tiny Dev Model",
        modelFileName: modelFileName,
        defaultConfigFileName: "analysis.cfg",
        checksum: try GokanModelChecksum(sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"),
        license: GokanModelLicense(name: "Fixture")
    )
}

private func sampleModelCatalogData() throws -> Data {
    let testsDirectory = URL(filePath: #filePath).deletingLastPathComponent()
    let packageRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: packageRoot.appending(path: "app/Shared/Resources/SampleModelCatalog.json"))
}
